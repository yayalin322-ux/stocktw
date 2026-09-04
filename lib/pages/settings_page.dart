import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import 'feedback_page.dart';
import 'glossary_page.dart';
import 'onboarding_page.dart';
import 'privacy_page.dart';
import 'terms_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _Header('外觀'),
          SwitchListTile(
            secondary: Icon(
                light ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: const Text('淺色模式'),
            subtitle: const Text('關閉則是預設的深色主題'),
            value: light,
            onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
          ),
          const Divider(),
          const _Header('新手'),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('名詞小百科'),
            subtitle: const Text('本益比、殖利率、填息、KD… 白話解釋'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GlossaryPage())),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('重看新手導覽'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OnboardingPage(
                    onDone: () => Navigator.pop(context)),
              ),
            ),
          ),
          const Divider(),
          const _Header('資料來源'),
          const ListTile(
            title: Text('即時報價 / 五檔'),
            subtitle: Text('證交所 MIS（免金鑰，約 5 秒更新一次）'),
          ),
          const ListTile(
            title: Text('K 線歷史'),
            subtitle: Text('Yahoo Finance chart（日/週/月 + 分鐘）'),
          ),
          const ListTile(
            title: Text('基本面 / 三大法人'),
            subtitle: Text('證交所 OpenAPI（前一交易日）'),
          ),
          const ListTile(
            title: Text('個股新聞'),
            subtitle: Text('Google News RSS'),
          ),
          const Divider(),
          const _Header('資料'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('立即更新報價'),
            onTap: () => ref.read(quotesProvider.notifier).refresh(),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.down),
            title: const Text('清除自選 / 持倉 / 提醒'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('確認清除？'),
                  content: const Text('會刪除所有自選股、持倉與提醒，無法復原。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('清除')),
                  ],
                ),
              );
              if (ok == true) {
                final p = ref.read(prefsProvider);
                await p.remove('watchlist');
                await p.remove('portfolio');
                await p.remove('alerts');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除，請重新啟動 App')),
                  );
                }
              }
            },
          ),
          const Divider(),
          const _Header('意見反饋'),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: AppColors.accent),
            title: const Text('意見反饋 / 客服'),
            subtitle: const Text('問題回報、功能建議，直接送到後台'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FeedbackPage())),
          ),
          const Divider(),
          const _Header('關於'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隱私權政策'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrivacyPage())),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('服務條款'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TermsPage())),
          ),
          const AboutListTile(
            applicationName: '股市 Pro',
            applicationVersion: '1.0.0',
            child: Text('關於'),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '本 App 僅供資訊參考，非投資建議。行情資料可能延遲。',
              style: TextStyle(color: AppColors.ink3, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: AppColors.ink3,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}
