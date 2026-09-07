/// 意見反饋的主題分類、常見問題、以及自動判斷輕重緩急。
library;

class FeedbackCategory {
  final String key;
  final String label;
  final List<({String q, String a})> faq;
  const FeedbackCategory(this.key, this.label, this.faq);
}

/// 「報價/資料錯誤」可再細分是哪一塊出問題（個股頁「回報這檔」用）
const kDataSubtypes = <String>[
  '報價 / 成交價',
  '分時走勢',
  'K 線',
  '五檔',
  '財報',
  '股利 / 除權息',
  '籌碼 / 法人',
  '新聞',
  '其他',
];

const kFeedbackCategories = <FeedbackCategory>[
  FeedbackCategory('crash', 'App 閃退 / 當機', [
    (
      q: 'App 一開就閃退怎麼辦？',
      a: '先重開手機再試一次；還是不行的話，用這個主題把「發生的畫面、什麼操作後閃退」寫給我們，會優先處理。'
    ),
    (
      q: '某個畫面卡住不動',
      a: '通常是網路不穩，下拉重新整理或切換分頁再回來。持續發生請回報是哪一頁。'
    ),
  ]),
  FeedbackCategory('data', '報價 / 資料錯誤', [
    (
      q: '報價跟券商不一樣？',
      a: '本 App 報價約 5 秒更新一次、來自證交所 MIS，盤中可能有幾秒延遲；成交明細請以券商為準。'
    ),
    (
      q: '財報 / 股利數字怪怪的',
      a: '資料來自證交所公開資料，偶有更新延遲。請把「股票代號 + 哪個數字不對 + 正確值」寫給我們。'
    ),
    (
      q: '除權息 / 行事曆日期不對',
      a: '證交所預告表會滾動更新，請提供代號，我們會對照。'
    ),
  ]),
  FeedbackCategory('feature', '功能建議', [
    (
      q: '想要新增某個功能',
      a: '直接寫需求跟使用情境，越具體越好（例如「希望自選股能分更多群組」）。'
    ),
  ]),
  FeedbackCategory('account', '通知 / 同步 / 小工具', [
    (
      q: '收不到到價提醒推播',
      a: '確認系統設定有開本 App 的通知；提醒是每分鐘背景比對，可能延遲 1–2 分鐘。'
    ),
    (
      q: '桌面小工具沒更新',
      a: '小工具是 App 在前景時寫入資料，開一下 App 就會更新；iOS 無法背景更新。'
    ),
    (
      q: 'QR 匯入 / 換手機',
      a: '在「設定 → 分享 / 匯入」用 QR 碼，可選擇要帶哪些資料。'
    ),
  ]),
  FeedbackCategory('other', '其他', []),
];

FeedbackCategory categoryOf(String key) => kFeedbackCategories.firstWhere(
      (c) => c.key == key,
      orElse: () => kFeedbackCategories.last,
    );

/// 依主題與內容關鍵字，自動給 0(低) / 1(中) / 2(高) 的優先度。
int autoPriority(String categoryKey, String subject, String body) {
  final text = '$subject $body';
  const urgent = [
    '閃退', '當機', '崩潰', '打不開', '開不起來', '一直跳出', '無法使用', '完全不能',
    '資料不見', '消失', '重大', '緊急', '錯誤', '亂碼', '當掉'
  ];
  const mid = ['不準', '不對', '怪怪', '延遲', '沒更新', '收不到', '慢', '卡'];
  if (categoryKey == 'crash') return 2;
  for (final w in urgent) {
    if (text.contains(w)) return 2;
  }
  for (final w in mid) {
    if (text.contains(w)) return 1;
  }
  if (categoryKey == 'data' || categoryKey == 'account') return 1;
  return 0;
}

const kPriorityLabel = ['低', '中', '高'];
