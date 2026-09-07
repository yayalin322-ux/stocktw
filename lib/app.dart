import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase/announcement.dart';
import 'pages/alerts_page.dart';
import 'pages/feedback_page.dart';
import 'pages/home_page.dart';
import 'pages/market_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/portfolio_page.dart';
import 'pages/watchlist_page.dart';
import 'state.dart';
import 'theme.dart';

class StockApp extends ConsumerStatefulWidget {
  const StockApp({super.key});
  @override
  ConsumerState<StockApp> createState() => _StockAppState();
}

class _StockAppState extends ConsumerState<StockApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 使用者在系統切換深/淺色時，若目前是「跟隨系統」就整個重繪
    if (ref.read(themeModeProvider) == AppThemeMode.system && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final sysLight =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.light;
    final light = switch (mode) {
      AppThemeMode.light => true,
      AppThemeMode.dark => false,
      AppThemeMode.system => sysLight,
    };
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
      return OnboardingPage(onDone: () => setState(() => _showOnboard = false));
    }

    if (!_announceChecked) {
      _announceChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        await maybeShowAnnouncement(context);
        if (context.mounted) await maybeShowFeedbackReplies(context);
      });
    }

    // 啟動報價輪詢
    ref.watch(quotesProvider);
    final tab = ref.watch(tabIndexProvider);
    final alertCount = ref
        .watch(alertsProvider)
        .where((a) => !a.triggered)
        .length;

    return Scaffold(
      body: IndexedStack(index: tab, children: _pages),
      // 安卓全螢幕手勢列 / 三鍵導覽會蓋在 App 上，底部留出系統安全區
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBarTheme(
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
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: '主頁',
              ),
              const NavigationDestination(
                icon: Icon(Icons.insights),
                label: '行情',
              ),
              const NavigationDestination(
                icon: Icon(Icons.star_border),
                label: '自選',
              ),
              const NavigationDestination(
                icon: Icon(Icons.pie_chart_outline),
                label: '持倉',
              ),
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
      ),
    );
  }
}
