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

// ---------- 到價提醒 ----------
async function runAlerts() {
  const snap = await db.collection("deviceAlerts").get();
  if (snap.empty) return console.log("無 deviceAlerts");

  const tw = new Map();
  const us = new Set();
  snap.forEach((d) => {
    for (const a of d.data().alerts || []) {
      if (a.triggered) continue;
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
      if (a.triggered) return a;
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
  await runBroadcasts();
  process.exit(0);
})();
