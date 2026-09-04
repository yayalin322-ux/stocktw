import 'package:flutter/material.dart';

import '../theme.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服務條款')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('最後更新：2026 年 9 月',
              style: TextStyle(fontSize: 12, color: AppColors.ink3)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warn.withValues(alpha: 0.5)),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '重要提醒：',
                    style: TextStyle(
                        color: AppColors.warn, fontWeight: FontWeight.w700)),
                TextSpan(
                  text: '本 App 提供的所有股價、指數、財報、技術指標、除權息、殖利率、'
                      '定期定額試算等資訊，僅供個人參考使用，不構成任何投資建議、勸誘或保證。'
                      '投資一定有風險，過去績效不代表未來表現，任何投資決策及其後果由你自行'
                      '負責，本 App 開發者不承擔任何相關損失責任。',
                ),
              ]),
              style: TextStyle(fontSize: 13.5, height: 1.7, color: AppColors.ink),
            ),
          ),
          const _Section('1. 服務內容', [
            '「股市 Pro」是一款免費的台股／美股看盤工具，提供即時報價、K 線技術分析、自選股、持倉損益試算、到價與技術面提醒、除權息行事曆、定期定額試算等功能。本 App 不提供下單、交易、資產保管等證券業務服務，也未取得任何金融監理機關的執照或許可。',
          ]),
          const _Section('2. 資料來源與準確性', [
            'App 內顯示的資料來自台灣證券交易所（TWSE）、證券櫃檯買賣中心、Yahoo Finance、Google News 等公開來源。這些資料可能有延遲、缺漏或錯誤，開發者已盡力校對，但不保證其完整性、即時性與正確性。使用前請自行以官方公告或券商系統為準。',
          ]),
          const _Section('3. 帳號與資料', [
            '本 App 不需要註冊帳號即可使用全部功能。你自行輸入的自選股、持倉、備忘錄等資料預設只存在你的裝置上；若啟用到價提醒推播，相關設定會同步一份到雲端資料庫以支援背景推播，詳見隱私權政策。',
          ]),
          const _Section('4. 使用限制', [
            '不得以任何形式對本 App 進行逆向工程、大量爬取資料、干擾正常運作或造成資料來源方（如證交所）的負擔。',
            '不得將本 App 的資料重製、轉售或用於其他商業服務。',
            '本 App 屬個人專案性質，功能與服務內容可能隨時調整、暫停或終止，恕不另行個別通知。',
          ]),
          const _Section('5. 免責聲明', [
            '本 App 依「現況」提供，不做任何明示或默示的保證，包括但不限於適售性、特定目的適用性、資料正確性等。在法律允許的最大範圍內，開發者對於因使用或無法使用本 App 所產生的任何直接、間接、附帶或衍生性損害，不負賠償責任。',
          ]),
          const _Section('6. 智慧財產權', [
            '本 App 的介面設計、程式碼與原創內容（不含第三方資料來源本身的內容）著作權歸開發者所有。',
          ]),
          const _Section('7. 條款修改', [
            '本條款可能不定期更新，更新後會調整本頁上方的日期。你繼續使用本 App 即視為同意最新版本的條款。',
          ]),
          const _Section('8. 準據法', [
            '本條款之解釋與適用，以中華民國法律為準據法。',
          ]),
          const _Section('9. 聯絡我們', [
            '有任何問題，歡迎透過 App 內「設定 → 意見反饋」與我們聯絡。',
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
