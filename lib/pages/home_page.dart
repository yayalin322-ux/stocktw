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
  List<IndexQuote> _idx = [];
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
    try {
      final idx = await marketService.indices();
      if (mounted) setState(() => _idx = idx);
    } catch (_) {}
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _goTab(int i) => ref.read(tabIndexProvider.notifier).state = i;

  IndexQuote? _find(String name) =>
      _idx.where((e) => e.name == name).firstOrNull;

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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
          children: [
            _indexStrip(),
            _quickCard(),
            _portfolioCard(pnl, value),
            _watchCard(watch, quotes),
            _alertCard(alerts, quotes),
            if (_news.isNotEmpty) _newsCard(),
          ],
        ),
      ),
    );
  }

  // ---------- 指數列 ----------
  Widget _indexStrip() {
    final taiex = _find('加權指數');
    final otc = _find('櫃買指數') ?? _find('上櫃指數');
    final nas = _find('那斯達克') ?? _find('Nasdaq') ?? _find('美國那斯達克');
    void open(IndexQuote? q, String fallbackSym, String name) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndexDetailPage(
                ySymbol: q?.ySymbol ?? fallbackSym, name: q?.name ?? name),
          ),
        );
    return Card(
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IndexCell(
                  name: '加權指數',
                  value: taiex?.value,
                  change: taiex?.change,
                  changePct: taiex?.changePct,
                  onTap: () => open(taiex, '^TWII', '加權指數'),
                ),
                const _VDiv(),
                IndexCell(
                  name: '櫃買指數',
                  value: otc?.value,
                  change: otc?.change,
                  changePct: otc?.changePct,
                  onTap: () => open(otc, '^TWOII', '櫃買指數'),
                ),
                const _VDiv(),
                IndexCell(
                  name: '那斯達克',
                  value: nas?.value,
                  change: nas?.change,
                  changePct: nas?.changePct,
                  onTap: () => open(nas, '^IXIC', '那斯達克'),
                ),
              ],
            ),
          ),
          if (_spark.length > 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SizedBox(
                height: 40,
                child: Sparkline(_spark,
                    baseline: taiex?.prevClose ?? double.nan),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 捷徑 ----------
  Widget _quickCard() {
    Widget item(IconData ic, String label, VoidCallback tap) => Expanded(
          child: InkWell(
            onTap: tap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ic, color: AppColors.accent, size: 21),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(children: [
          item(Icons.insights, '行情', () => _goTab(1)),
          item(Icons.filter_list, '選股', () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScreenerPage()))),
          item(Icons.event_outlined, '除權息', () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ExCalendarPage()))),
          item(Icons.menu_book_outlined, '名詞', () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GlossaryPage()))),
        ]),
      ),
    );
  }

  // ---------- 持倉 ----------
  Widget _portfolioCard(double pnl, double value) {
    return Card(
      child: Column(
        children: [
          PanelHeader('我的持倉', onMore: () => _goTab(3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('未實現損益',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.ink3)),
                    const SizedBox(height: 2),
                    Text(signed(pnl, 0),
                        style: kNum.copyWith(
                            fontSize: 23, color: AppColors.forChange(pnl))),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('總市值',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.ink3)),
                    const SizedBox(height: 2),
                    Text(nf0.format(value),
                        style: kNum.copyWith(fontSize: 17)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 自選 ----------
  Widget _watchCard(List<Symbol> watch, Map<String, Quote> quotes) {
    return Card(
      child: Column(
        children: [
          PanelHeader('我的自選', onMore: () => _goTab(2)),
          if (watch.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('尚無自選股',
                    style: TextStyle(color: AppColors.ink3, fontSize: 13)),
              ),
            )
          else
            for (final s in watch.take(6)) ...[
              const Divider(height: 1),
              MarketTickerRow(
                name: quotes[s.id]?.name ?? '',
                code: s.code,
                price: quotes[s.id]?.price,
                change: quotes[s.id]?.change,
                changePct: quotes[s.id]?.changePct,
                isLimitUp: quotes[s.id]?.isLimitUp ?? false,
                isLimitDown: quotes[s.id]?.isLimitDown ?? false,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuoteDetailPage(
                        symbol: s, name: quotes[s.id]?.name ?? s.code),
                  ),
                ),
              ),
            ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ---------- 提醒 ----------
  Widget _alertCard(List<PriceAlert> alerts, Map<String, Quote> quotes) {
    final active = alerts.where((a) => !a.triggered).toList();
    final triggered = alerts.where((a) => a.triggered).length;
    return Card(
      child: Column(
        children: [
          PanelHeader('到價提醒', onMore: () => _goTab(4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Align(
              alignment: Alignment.centerLeft,
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
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.ink2),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 頭條 ----------
  Widget _newsCard() {
    return Card(
      child: Column(
        children: [
          const PanelHeader('財經頭條'),
          for (final n in _news.take(6)) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => launchUrl(Uri.parse(n.url),
                  mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                        color: AppColors.ink3, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.3)),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _VDiv extends StatelessWidget {
  const _VDiv();
  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: AppColors.border);
}
