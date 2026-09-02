# 後台設定（免信用卡版）

三個功能：**開啟頁公告/廣告**、**到價提醒背景推播**、**管理後台網頁**。
沒設定前 App 照常跑，只是這三個功能停用。

- 公告 + 管理後台 → Firebase **Spark 免費方案**（不用信用卡）
- 背景推播的「排程比價」→ 放 **GitHub Actions**（免費），不放 Cloud Functions

---

## 1. 建 Firebase 專案（Spark 免費，不升 Blaze）

1. https://console.firebase.google.com → 新增專案（例：`stocktw`）
2. 專案裡開啟：
   - **Firestore Database** → 建立 → 正式模式 → 位置 `asia-east1`
   - **Authentication** → 登入方式 → 啟用 **Google**
   - **Hosting** → 開始使用（點過即可）
   - Cloud Messaging（預設就有）
   - ⚠️ **不用升 Blaze、不用綁卡**

## 2. 連結專案（不要 `firebase init`，檔案都寫好了）

```bash
cd ~/dev/stocktw
firebase use --add        # 選剛建的專案，別名打 default
```

## 3. 接上 App

```bash
dart pub global activate flutterfire_cli
flutterfire configure     # 選同一個專案，平台勾 android + ios
```

會產生 `lib/firebase_options.dart`（覆蓋佔位檔）。

- **iOS 推播**還要：Apple Developer 開 Push Notifications capability，
  並在 Firebase 專案設定 → Cloud Messaging → 上傳 APNs 金鑰。

## 4. 填 email / 設定（2 個地方）

| 檔案 | 改什麼 |
|---|---|
| `firestore.rules` | `YOUR_EMAIL@example.com` → 你的 Google 帳號 |
| `hosting/public/index.html` | `firebaseConfig = {...}` → 貼 **web 版**設定（console → 專案設定 → 你的應用程式 → 沒 web app 就「新增應用程式 → Web」）|

## 5. 部署 Firestore 規則 + 管理後台

```bash
cd ~/dev/stocktw
firebase deploy --only firestore:rules,hosting
```

完成印出管理後台網址 `https://<專案>.web.app`。

## 6. 背景推播：GitHub Actions

1. 專案推到 GitHub（private 也可）：
   ```bash
   cd ~/dev/stocktw
   git remote add origin git@github.com:<你的帳號>/stocktw.git
   git push -u origin main
   ```
2. Firebase console → ⚙️ 專案設定 → **服務帳戶** → 「產生新的私密金鑰」→ 下載 JSON
3. GitHub repo → Settings → Secrets and variables → Actions → **New repository secret**
   - 名稱：`FIREBASE_SERVICE_ACCOUNT`
   - 內容：把整個 JSON 檔內容貼進去
4. GitHub repo → Actions 分頁 → 啟用 workflows。之後 `.github/workflows/check-alerts.yml`
   會每 15 分鐘自動跑（也可在 Actions 頁按 **Run workflow** 立刻測）。

---

## 運作方式

| 元件 | 做什麼 | 在哪 |
|---|---|---|
| `lib/firebase/announcement.dart` | App 啟動讀 `config/announcement`，未看過版本跳 dialog | App |
| `lib/firebase/push.dart` | 取 FCM token 寫 `devices/{token}`；提醒變動同步 `deviceAlerts/{token}` | App |
| `tools/check-alerts/index.js` | 讀所有 `deviceAlerts` 比價 → 命中發 FCM；讀 `broadcasts` 佇列 → 全體推播 | GitHub Actions |
| `hosting/public/index.html` | Google 登入的管理頁：改公告、看裝置數、排廣播 | Firebase Hosting |

## 費用

全部 0 元：Firestore/FCM/Hosting 在 Spark 免費額度內；GitHub Actions
公開 repo 免費、私有 repo 每月 2000 分鐘免費（這個 job 每次幾十秒）。

## 想改回 Cloud Functions？

之後若升 Blaze，把 `tools/check-alerts/index.js` 的邏輯搬進
`functions/index.js` 用 `onSchedule` 包起來、`firebase.json` 加回 functions 區塊即可。
