import 'package:flutter/material.dart';

import '../theme.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隱私權政策')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('最後更新：2026 年 9 月',
              style: TextStyle(fontSize: 12, color: AppColors.ink3)),
          SizedBox(height: 16),
          Text(
            '「股市 Pro」（以下稱「本 App」）由個人開發者製作與維運。我們非常重視你的隱私，'
            '這份政策說明本 App 會蒐集哪些資料、用來做什麼、存在哪裡，以及你有哪些選擇。',
            style: TextStyle(fontSize: 14, height: 1.7, color: AppColors.ink2),
          ),
          _Section('1. 我們會蒐集哪些資料', [
            '自選股、持倉、到價提醒、備忘錄：預設只存在你手機的本機儲存空間，不會上傳到任何伺服器，你解除安裝 App 就會一併刪除。',
            '推播權杖（FCM Token）：如果你允許通知，本 App 會把裝置的推播權杖，以及你設定的到價提醒內容（股票代號、目標價、均線條件等），同步一份到 Firebase Firestore 資料庫，讓背景排程能在 App 沒開啟時比對報價、推播通知給你。這份資料不含你的姓名、電話、Email 或其他可辨識身分的個人資料。',
            'QR 碼匯出/匯入自選股與持倉：資料直接編碼在 QR 圖片裡，手機對手機掃描讀取，不會經過我們的伺服器。',
            '意見反饋：如果你在「意見反饋」頁送出訊息，內容（含你選填的聯絡方式）會存進後台資料庫，只用來處理你的回饋。',
            '我們不會要求你註冊帳號、蒐集你的姓名/電話/位置資訊，也不會有第三方廣告或分析追蹤 SDK。',
          ]),
          _Section('2. 資料怎麼被使用', [
            '推播權杖與提醒內容僅用於「到價/技術面提醒的背景推播」這個單一用途，不會被用於廣告投放、使用者輪廓分析，也不會出售或提供給第三方。',
          ]),
          _Section('3. 資料存放與安全', [
            '雲端資料存放在 Google Firebase（Firestore），存取權限透過 Firebase 安全規則限制，只有你的裝置（用權杖驗證）跟開發者本人（管理後台）能讀寫。',
          ]),
          _Section('4. 第三方資料來源', [
            '本 App 顯示的報價、K 線、財報、新聞等內容，來自台灣證券交易所（TWSE）、證券櫃檯買賣中心、Yahoo Finance、Google News 等公開資料來源，僅供參考，本 App 不保證其即時性與正確性，亦不對其內容負責。',
          ]),
          _Section('5. 你的選擇與權利', [
            '可以隨時在「設定」頁關閉通知權限，之後就不會再有新的提醒資料同步到雲端。',
            '可以在「設定」頁一鍵清除本機所有自選股/持倉/提醒資料。',
            '如果想要求刪除雲端上跟你裝置有關的資料，可以透過 App 內「意見反饋」功能告訴我們，附上大概的操作時間，我們會協助處理。',
          ]),
          _Section('6. 兒童隱私', [
            '本 App 不是特別為兒童設計，也不會刻意蒐集 13 歲以下使用者的個人資料。',
          ]),
          _Section('7. 政策異動', [
            '若這份政策有重大變更，會更新本頁上方的「最後更新」日期。建議偶爾回來看看。',
          ]),
          _Section('8. 聯絡我們', [
            '有任何隱私相關問題，歡迎透過 App 內「設定 → 意見反饋」與我們聯絡。',
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> paragraphs;
  const _Section(this.title, this.paragraphs);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
          const SizedBox(height: 8),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(p,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.7, color: AppColors.ink2)),
            ),
        ],
      ),
    );
  }
}
