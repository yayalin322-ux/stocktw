# 台股 Pro

Flutter（Android + iOS）專業台股 App。即時報價、K 線技術指標、持倉損益、到價提醒。
所有資料來源皆免金鑰。

## 功能

| 分頁 | 內容 |
|---|---|
| **自選** | 多股清單、6 秒輪詢、依漲跌幅/股價/量排序、拖曳排序、左滑刪除 |
| **個股頁** | 即時表頭（現價/漲跌/開高低/量/漲跌停）＋ `k_chart_plus` K 線（日/週/月/5分/60分）＋ MA·EMA·BOLL·SAR·MACD·KDJ·RSI·WR·CCI 指標切換 ＋ 五檔買賣 ＋ 個股新聞 ＋ 籌碼/基本面 |
| **持倉** | 輸入張數與成本，即時市值、未實現損益、報酬率，總覽卡片 |
| **提醒** | 設定漲到/跌到目標價，命中時本地推播通知 |

## 資料來源（免金鑰）

| 資料 | 來源 | 檔案 |
|---|---|---|
| 即時報價 + 五檔 | 證交所 MIS `getStockInfo.jsp` | `lib/services/quote_service.dart` |
| K 線歷史 | Yahoo Finance `v8/finance/chart`（`.TW` / `.TWO`）| `lib/services/candle_service.dart` |
| PER / PBR / 殖利率 | 證交所 OpenAPI `BWIBBU_ALL` | `lib/services/fundamentals_service.dart` |
| 三大法人買賣超 | 證交所 `rwd/zh/fund/T86` 日報 | 同上 |
| 個股新聞 | Google News RSS | `lib/services/news_service.dart` |

行動端無 CORS，App 直接呼叫上述端點，不需要自架 proxy。

## 專案結構

```
lib/
  main.dart            進入點（載入 SharedPreferences、初始化通知）
  app.dart             MaterialApp + 底部四分頁
  theme.dart           深色主題、漲紅跌綠色票
  models.dart          Quote / Candle / Position / PriceAlert / NewsItem / Fundamentals
  state.dart           Riverpod：watchlist / portfolio / alerts / 報價輪詢 + 提醒判斷
  services/            api(dio) / quote / candle / news / fundamentals / notifications
  pages/               watchlist / quote_detail / portfolio / alerts / settings / add_symbol_sheet
bin/smoke.dart         資料層煙霧測試：dart run bin/smoke.dart
```

## 開發

```bash
flutter pub get
dart run bin/smoke.dart      # 驗證資料層（不需模擬器）
flutter run                  # 需要模擬器 / 實機
```

### 首次在本機建置需要

- **iOS / macOS**：安裝完整版 Xcode（非僅 Command Line Tools），然後
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`、
  `sudo xcodebuild -runFirstLaunch`，並安裝 CocoaPods（`sudo gem install cocoapods`）。
- **Android**：安裝 Android Studio 或 Android SDK，`flutter config --android-sdk <path>`。

`flutter doctor` 綠燈後即可 `flutter run`。

## 免責

行情資料可能延遲，本 App 僅供資訊參考，非投資建議。
