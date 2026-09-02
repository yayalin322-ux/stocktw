import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../market_session.dart';
import '../models.dart';
import '../services/market_service.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ex_calendar_page.dart';
import 'glossary_page.dart';
import 'index_detail_page.dart';
import 'quote_detail_page.dart';
import 'screener_page.dart';
import 'settings_page.dart';
import 'search_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  IndexQuote? _taiex;
  List<double> _spark = [];
  List<NewsHead> _news = [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _loadLive());
  }

  Future<void> _load() async {
    await _loadLive();
    final spark = await marketService.taiexIntraday();
    final news = await marketService.headlines();
    if (!mounted) return;
    setState(() {
      _spark = spark.map((c) => c.close).toList();
      _news = news;
    });
  }

  Future<void> _loadLive() async {
    final idx = await marketService.indices();
    if (mounted) {
      setState(() =>
          _taiex = idx.where((e) => e.name == '加權指數').firstOrNull);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _goTab(int i) => ref.read(tabIndexProvider.notifier).state = i;

  @override
  Widget build(BuildContext context) {
    final positions = ref.watch(portfolioProvider);
    final quotes = ref.watch(quotesProvider);
    final watch = ref.watch(watchlistProvider);
    final alerts = ref.watch(alertsProvider);

    double cost = 0, value = 0;
    for (final p in positions) {
      final px = quotes[Symbol(p.code, p.market).id]?.price;
      cost += p.costValue;
      value += px != null ? p.marketValue(px) : p.costValue;
    }
    final pnl = value - cost;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: const [
          Text('台股 Pro'),
          SizedBox(width: 10),
          SessionPill(),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _taiexCard(),
            const SizedBox(height: 12),
            _quickRow(),
            const SizedBox(height: 12),
            _portfolioCard(pnl, value),
            const SizedBox(height: 12),
            _watchCard(watch, quotes),
            const SizedBox(height: 12),
            _alertCard(alerts, quotes),
            const SizedBox(height: 12),
            if (_news.isNotEmpty) _newsCard(),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, {VoidCallback? more, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.ink3,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (more != null)
                GestureDetector(
                  onTap: more,
                  child: const Text('查看全部 ›',
                      style: TextStyle(fontSize: 12, color: AppColors.accent)),
                ),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _taiexCard() {
    final t = _taiex;
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndexDetailPage(
                ySymbol: t?.ySymbol ?? '^TWII', name: '加權指數'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('加權指數',
                  style: TextStyle(color: AppColors.ink3, fontSize: 13)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(t?.value?.toStringAsFixed(2) ?? '--',
                    style: kNum.copyWith(
                        fontSize: 32,
                        color: t?.change == null
                            ? AppColors.ink
                            : AppColors.forChange(t!.change!))),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ChangeText(t?.change, t?.changePct, size: 14),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 54,
                child: _spark.length > 2
                    ? Sparkline(_spark,
                        baseline: t?.prevClose ?? double.nan)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickRow() {
    Widget item(IconData ic, String label, VoidCallback tap) => Expanded(
          child: InkWell(
            onTap: tap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(ic, color: AppColors.accent),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        );
    return Card(
      child: Row(children: [
        item(Icons.insights, '行情', () => _goTab(1)),
        item(Icons.filter_list, '選股', () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScreenerPage()));
        }),
        item(Icons.event_outlined, '除權息', () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ExCalendarPage()));
        }),
        item(Icons.menu_book_outlined, '名詞', () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GlossaryPage()));
        }),
      ]),
    );
  }

  Widget _portfolioCard(double pnl, double value) {
    return _section(
      '我的持倉',
      more: () => _goTab(3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('未實現損益',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3)),
              Text(signed(pnl, 0),
                  style: kNum.copyWith(
                      fontSize: 24, color: AppColors.forChange(pnl))),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('總市值',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3)),
              Text(nf0.format(value), style: kNum.copyWith(fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _watchCard(List<Symbol> watch, Map<String, Quote> quotes) {
    return _section(
      '我的自選',
      more: () => _goTab(2),
      child: watch.isEmpty
          ? const Text('尚無自選股',
              style: TextStyle(color: AppColors.ink3, fontSize: 13))
          : Column(
              children: [
                for (final s in watch.take(5))
                  InkWell(
                    onTap: () {
                      final q = quotes[s.id];
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuoteDetailPage(
                              symbol: s, name: q?.name ?? s.code),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              quotes[s.id]?.name.isNotEmpty == true
                                  ? quotes[s.id]!.name
                                  : s.code,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text(quotes[s.id]?.price?.toStringAsFixed(2) ?? '--',
                            style: kNum.copyWith(fontSize: 14)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 92,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ChangeText(quotes[s.id]?.change,
                                quotes[s.id]?.changePct,
                                size: 12),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _alertCard(List<PriceAlert> alerts, Map<String, Quote> quotes) {
    final active = alerts.where((a) => !a.triggered).toList();
    final triggered = alerts.where((a) => a.triggered).length;
    return _section(
      '到價提醒',
      more: () => _goTab(4),
      child: alerts.isEmpty
          ? const Text('尚無提醒',
              style: TextStyle(color: AppColors.ink3, fontSize: 13))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('待觸發 ${active.length} 檔　已觸發 $triggered 檔',
                    style: const TextStyle(fontSize: 13)),
                for (final a in active.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${a.name} ${a.above ? "漲到" : "跌到"} ${a.target.toStringAsFixed(2)}'
                      '${quotes[Symbol(a.code, a.market).id]?.price != null ? "（現 ${quotes[Symbol(a.code, a.market).id]!.price!.toStringAsFixed(2)}）" : ""}',
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.ink2),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _newsCard() {
    return _section(
      '財經頭條',
      child: Column(
        children: [
          for (final n in _news.take(6))
            InkWell(
              onTap: () => launchUrl(Uri.parse(n.url),
                  mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: AppColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
