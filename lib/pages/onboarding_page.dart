import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

const kOnboardKey = 'onboarded_v3';

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.icon, this.title, this.body);
}

const _slides = [
  _Slide(Icons.home_outlined, '主頁 = 你的總覽',
      '「主頁」把加權指數、你的持倉損益、自選股、到價提醒、財經頭條整合在一頁，'
          '上方四個快捷可到行情、選股、除權息、名詞小百科。'),
  _Slide(Icons.insights, '行情看各國指數',
      '「行情」分頁有加權、櫃買、那斯達克、道瓊、日經、上證、韓國，還有美元匯率、'
          '三大法人買賣超、成交量前 20；每個指數都能點進去看歷史線圖。'),
  _Slide(Icons.search, '搜尋任何股票',
      '任何頁面右上放大鏡，打「2330」或「台積」都行；打英文（AAPL、Nvidia）會查美股。'
          '點結果可直接看，不用先加自選；想收藏再按 ⭐。'),
  _Slide(Icons.candlestick_chart, '個股：K線・分時・指標',
      '個股頁上方切「分時 / 日K / 週K…」，K線下方可開關 MA、MACD、KD、RSI 等指標，'
          '每個指標旁有「?」白話解釋。下面分頁看五檔、財報、股利/除權息、籌碼、新聞。'),
  _Slide(Icons.notifications_active_outlined, '持倉損益・到價提醒',
      '在個股頁底部「記錄持倉」輸入張數成本，App 幫你算即時損益；'
          '「到價提醒」設目標價，碰到就推播通知你。'),
  _Slide(Icons.menu_book_outlined, '看不懂的字，點「?」',
      '本益比、殖利率、填息、KD… 看到不懂的詞，點旁邊的 ? 就有白話說明。'
          '「設定 → 名詞小百科」可以整本翻。'),
];

class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _c = PageController();
  int _i = 0;

  Future<void> _finish() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kOnboardKey, true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('跳過'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _c,
                onPageChanged: (v) => setState(() => _i = v),
                itemCount: _slides.length,
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s.icon, size: 72, color: AppColors.accent),
                        const SizedBox(height: 28),
                        Text(s.title,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 16),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15,
                                height: 1.8,
                                color: AppColors.ink2)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var j = 0; j < _slides.length; j++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: j == _i ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: j == _i ? AppColors.accent : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (last) {
                      _finish();
                    } else {
                      _c.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut);
                    }
                  },
                  child: Text(last ? '開始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
