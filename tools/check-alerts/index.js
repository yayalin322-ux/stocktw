/**
 * 到價提醒排程比價 + FCM 推播（跑在 GitHub Actions，不需 Firebase Blaze）
 *
 * 環境變數：
 *   FIREBASE_SERVICE_ACCOUNT  Firebase 服務帳號 JSON 字串（GitHub secret）
 *
 * 做兩件事：
 *   1. 讀 deviceAlerts/*，抓 MIS/Yahoo 報價，命中的提醒 → 推播該裝置 + 標記 triggered
 *   2. 讀 broadcasts/*（sent!=true）→ 推播所有裝置 → 標記 sent
 */
const admin = require("firebase-admin");

const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || "{}");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const fcm = admin.messaging();

// ---------- 報價 ----------
async function twQuotes(list) {
  if (!list.length) return {};
  const exch = list.map((c) => `${c.market}_${c.code}.tw`).join("|");
  const url =
    `https://mis.twse.com.tw/stock/api/getStockInfo.jsp?json=1&delay=0` +
    `&_=${Date.now()}&ex_ch=${encodeURIComponent(exch)}`;
  const out = {};
  for (let attempt = 0; attempt < 3 && Object.keys(out).length < list.length; attempt++) {
    if (attempt) await new Promise((r) => setTimeout(r, 400));
    try {
      const r = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0",
          Referer: "https://mis.twse.com.tw/stock/index.jsp",
        },
      });
      const j = await r.json();
      for (const m of j.msgArray || []) {
        const px =
          parseFloat(m.z) || parseFloat(m.pz) || parseFloat(m.o) || parseFloat(m.y);
        if (m.c && px > 0) {
          const ex = m.ex === "otc" ? "otc" : "tse";
          out[`${ex}:${m.c}`] = px;
        }
      }
    } catch (e) {
      console.error("twQuotes", e.message);
    }
  }
  return out;
}

async function usQuote(code) {
  try {
    const r = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(
        code
      )}?range=1d&interval=1d`,
      { headers: { "User-Agent": "Mozilla/5.0" } }
    );
    const j = await r.json();
    return j?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null;
  } catch {
    return null;
  }
}

// ---------- 均線（技術面提醒用） ----------
function yahooSymbol(code, market) {
  if (market === "us") return code;
  return market === "otc" ? `${code}.TWO` : `${code}.TW`;
}

async function dailyCloses(code, market) {
  try {
    const sym = yahooSymbol(code, market);
    const r = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(
        sym
      )}?range=3mo&interval=1d`,
      { headers: { "User-Agent": "Mozilla/5.0" } }
    );
    const j = await r.json();
    const res = j?.chart?.result?.[0];
    const closes = res?.indicators?.quote?.[0]?.close || [];
    return closes.filter((c) => c != null);
  } catch (e) {
    console.error("dailyCloses", code, e.message);
    return [];
  }
}

function sma(closes, period, idx) {
  if (idx - period + 1 < 0) return null;
  let sum = 0;
  for (let i = idx - period + 1; i <= idx; i++) sum += closes[i];
  return sum / period;
}

// ---------- 技術面提醒（均線站上/跌破） ----------
async function runMaCrossAlerts() {
  const snap = await db.collection("deviceAlerts").get();
  if (snap.empty) return;

  let hits = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const token = data.token;
    if (!token) continue;
    const alerts = data.alerts || [];
    let changed = false;
    for (let i = 0; i < alerts.length; i++) {
      const a = alerts[i];
      if (a.triggered || a.kind !== "ma_cross") continue;
      const period = a.maPeriod || 20;
      const closes = await dailyCloses(a.code, a.market);
      if (closes.length < period + 2) continue;
      const n = closes.length;
      const maPrev = sma(closes, period, n - 2);
      const maNow = sma(closes, period, n - 1);
      if (maPrev == null || maNow == null) continue;
      const prevClose = closes[n - 2];
      const nowClose = closes[n - 1];
      const crossUp = a.crossUp !== false;
      const hit = crossUp
        ? prevClose < maPrev && nowClose >= maNow
        : prevClose > maPrev && nowClose <= maNow;
      if (!hit) continue;
      alerts[i] = { ...a, triggered: true };
      changed = true;
      hits++;
      fcm
        .send({
          token,
          notification: {
            title: `${a.name} ${a.code} 技術面提醒`,
            body: `${crossUp ? "站上" : "跌破"} MA${period}（現價 ${nowClose.toFixed(2)}）`,
          },
        })
        .catch((e) => console.error("send", e.message));
    }
    if (changed) {
      await doc.ref.update({
        alerts,
        checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
  console.log(`技術面提醒命中 ${hits} 則`);
}

// ---------- 到價提醒 ----------
async function runAlerts() {
  const snap = await db.collection("deviceAlerts").get();
  if (snap.empty) return console.log("無 deviceAlerts");

  const tw = new Map();
  const us = new Set();
  snap.forEach((d) => {
    for (const a of d.data().alerts || []) {
      if (a.triggered || a.kind === "ma_cross") continue;
      if (a.market === "us") us.add(a.code);
      else tw.set(`${a.market}:${a.code}`, { code: a.code, market: a.market });
    }
  });

  const prices = await twQuotes([...tw.values()]);
  for (const code of us) {
    const p = await usQuote(code);
    if (p != null) prices[`us:${code}`] = p;
  }
  console.log("報價", prices);

  let hits = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const token = data.token;
    if (!token) continue;
    let changed = false;
    const next = (data.alerts || []).map((a) => {
      if (a.triggered || a.kind === "ma_cross") return a;
      const key = a.market === "us" ? `us:${a.code}` : `${a.market}:${a.code}`;
      const px = prices[key];
      if (px == null) return a;
      const hit = a.above ? px >= a.target : px <= a.target;
      if (!hit) return a;
      changed = true;
      hits++;
      fcm
        .send({
          token,
          notification: {
            title: `${a.name} ${a.code} 到價`,
            body: `${a.above ? "漲抵" : "跌抵"} ${Number(a.target).toFixed(
              2
            )}（現價 ${px.toFixed(2)}）`,
          },
        })
        .catch((e) => console.error("send", e.message));
      return { ...a, triggered: true };
    });
    if (changed) {
      await doc.ref.update({
        alerts: next,
        checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
  console.log(`命中 ${hits} 則`);
}

// ---------- 廣播佇列 ----------
async function runBroadcasts() {
  const q = await db
    .collection("broadcasts")
    .where("sent", "==", false)
    .limit(5)
    .get();
  if (q.empty) return;

  const devs = await db.collection("devices").get();
  const tokens = devs.docs.map((d) => d.data().token).filter(Boolean);

  for (const doc of q.docs) {
    const b = doc.data();
    let ok = 0;
    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      if (!batch.length) break;
      const res = await fcm.sendEachForMulticast({
        tokens: batch,
        notification: { title: b.title, body: b.body || "" },
      });
      ok += res.successCount;
    }
    await doc.ref.update({
      sent: true,
      sentCount: ok,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`廣播「${b.title}」送出 ${ok} 台`);
  }
}

// ---------- 意見反饋回覆推播 ----------
async function runFeedbackReplies() {
  const snap = await db.collection("feedback").get();
  let sent = 0, skipped = 0, failed = 0;
  for (const doc of snap.docs) {
    const v = doc.data();
    if (v.replyNotified === true) continue;
    // 新版：messages 陣列裡有 admin 訊息；舊版：v.reply 字串
    const msgs = Array.isArray(v.messages) ? v.messages : [];
    const lastAdmin = [...msgs].reverse().find((m) => m.from === "admin");
    const body = lastAdmin ? lastAdmin.text : v.reply;
    if (!body) continue;

    const token = v.deviceToken;
    if (!token) {
      // 這張票沒有可推播的裝置（例如 iOS 沒拿到 APNs token）。
      // 不要把它標成 replyNotified，之後 App 端補上 token 或 App 開著時
      // 由 FeedbackWatch 本機補一則通知。避免無限重試就記個計數。
      const tries = (v.replyNoTokenTries || 0) + 1;
      await doc.ref.update({
        replyNoTokenTries: tries,
        ...(tries >= 20 ? { replyNotified: true } : {}),
      });
      skipped++;
      continue;
    }

    try {
      await fcm.send({
        token,
        notification: {
          title: "開發者回覆了你的意見反饋",
          body: body.length > 120 ? body.slice(0, 120) + "…" : body,
        },
        data: { kind: "feedback_reply", ticketId: doc.id },
      });
      await doc.ref.update({ replyNotified: true, replyNoTokenTries: 0 });
      sent++;
    } catch (e) {
      const code = e.errorInfo?.code || e.code || "";
      console.error("feedback reply send", doc.id, code, e.message);
      // token 失效 → 這台裝置收不到了，標記完成免得每次都重試
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-argument") ||
        code.includes("invalid-registration-token")
      ) {
        await doc.ref.update({ replyNotified: true });
      } else {
        const tries = (v.replySendTries || 0) + 1;
        await doc.ref.update({
          replySendTries: tries,
          ...(tries >= 8 ? { replyNotified: true } : {}),
        });
      }
      failed++;
    }
  }
  console.log(
    `意見反饋回覆推播：送出 ${sent}、無 token ${skipped}、失敗 ${failed}`
  );
}

// ---------- 意見反饋維護 ----------
// 1. 已結案（status==closed）：10 天後刪除雲端資料（使用者手機保留本地副本）
// 2. 等使用者確認結案（status==pending_user_close）：14 天沒回應 → 視同同意，自動結案
async function runFeedbackCleanup() {
  const snap = await db.collection("feedback").get();
  const now = Date.now();
  const delCutoff = now - 10 * 24 * 60 * 60 * 1000;
  const autoCloseCutoff = now - 14 * 24 * 60 * 60 * 1000;
  let removed = 0, autoClosed = 0;
  for (const doc of snap.docs) {
    const v = doc.data();
    if (v.status === "closed") {
      const closedMs = v.closedAt?.toMillis ? v.closedAt.toMillis() : 0;
      if (closedMs && closedMs < delCutoff) {
        await doc.ref.delete();
        removed++;
      }
    } else if (v.status === "pending_user_close") {
      const upMs = v.updatedAt?.toMillis ? v.updatedAt.toMillis() : 0;
      if (upMs && upMs < autoCloseCutoff) {
        await doc.ref.update({
          status: "closed",
          closedAt: admin.firestore.FieldValue.serverTimestamp(),
          autoClosed: true,
        });
        autoClosed++;
      }
    }
  }
  console.log(`清除已結案反饋 ${removed} 筆、逾時自動結案 ${autoClosed} 筆`);
}

process.on("unhandledRejection", (e) => {
  console.error("unhandledRejection", e);
});

(async () => {
  const steps = [
    ["runAlerts", runAlerts],
    ["runMaCrossAlerts", runMaCrossAlerts],
    ["runBroadcasts", runBroadcasts],
    ["runFeedbackReplies", runFeedbackReplies],
    ["runFeedbackCleanup", runFeedbackCleanup],
  ];
  for (const [name, fn] of steps) {
    try {
      await fn();
    } catch (e) {
      console.error(`[${name}] 失敗：`, e && e.stack ? e.stack : e);
    }
  }
  // 等 stdout 排空再結束（CI 下 process.exit 會截斷輸出）
  await new Promise((r) => setTimeout(r, 200));
})();
