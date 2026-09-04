import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase/announcement.dart';
import 'pages/alerts_page.dart';
import 'pages/home_page.dart';
import 'pages/market_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/portfolio_page.dart';
import 'pages/watchlist_page.dart';
import 'state.dart';
import 'theme.dart';

class StockApp extends ConsumerWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = ref.watch(themeModeProvider);
    AppColors.setLight(light);
    // 切換主題時用 key 強制整棵 MaterialApp 重建，確保所有畫面（含已經
    // 開著的頁面）都套用新的顏色，不會有部分頁面沒跟著換。
    return MaterialApp(
      key: ValueKey(light),
      title: '股市 Pro',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _showOnboard = false;

  static const _pages = [
    HomePage(),
    MarketPage(),
    WatchlistPage(),
    PortfolioPage(),
    AlertsPage(),
  ];

  bool _announceChecked = false;

  @override
  void initState() {
    super.initState();
    _showOnboard = !(ref.read(prefsProvider).getBool(kOnboardKey) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboard) {
      return OnboardingPage(
          onDone: () => setState(() => _showOnboard = false));
    }

    if (!_announceChecked) {
      _announceChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowAnnouncement(context);
      });
    }

    // 啟動報價輪詢
    ref.watch(quotesProvider);
    final tab = ref.watch(tabIndexProvider);
    final alertCount =
        ref.watch(alertsProvider).where((a) => !a.triggered).length;

    return Scaffold(
      body: IndexedStack(index: tab, children: _pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accent.withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: tab,
          onDestinationSelected: (i) =>
              ref.read(tabIndexProvider.notifier).state = i,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), label: '主頁'),
            const NavigationDestination(icon: Icon(Icons.insights), label: '行情'),
            const NavigationDestination(
                icon: Icon(Icons.star_border), label: '自選'),
            const NavigationDestination(
                icon: Icon(Icons.pie_chart_outline), label: '持倉'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: alertCount > 0,
                label: Text('$alertCount'),
                child: const Icon(Icons.notifications_none),
              ),
              label: '提醒',
            ),
          ],
        ),
      ),
    );
  }
}
