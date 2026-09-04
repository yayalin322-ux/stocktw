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

(async () => {
  await runAlerts();
  await runMaCrossAlerts();
  await runBroadcasts();
  process.exit(0);
})();
