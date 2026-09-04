import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../market_session.dart';
import '../models.dart';
import '../services/market_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ex_calendar_page.dart';
import 'index_detail_page.dart';
import 'quote_detail_page.dart';
import 'screener_page.dart';
import 'search_page.dart';

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  List<IndexQuote> _idx = [];
  List<double> _spark = [];
  List<InstFlow> _inst = [];
  List<HotStock> _hot = [];
  IndexQuote? _fx;
  Timer? _t;

  static const _stripNames = {'加權指數', '櫃買指數', '那斯達克'};

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 12), (_) => _loadLive());
  }

  Future<void> _load() async {
    await _loadLive();
    final inst = await marketService.institutions();
    final hot = await marketService.hot();
    final spark = await marketService.taiexIntraday();
    final fx = await marketService.fx();
    if (!mounted) return;
    setState(() {
      _inst = inst;
      _hot = hot;
      _spark = spark.map((c) => c.close).toList();
      _fx = fx;
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

  void _open(String code, String name, Market m) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                QuoteDetailPage(symbol: Symbol(code, m), name: name)),
      );

  void _openIndex(IndexQuote q) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => IndexDetailPage(ySymbol: q.ySymbol, name: q.name)),
      );

  IndexQuote? _find(String name) =>
      _idx.where((e) => e.name == name).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final taiex = _find('加權指數');
    final groups = <String, List<IndexQuote>>{};
    for (final q in _idx) {
      if (_stripNames.contains(q.name)) continue;
      groups.putIfAbsent(q.group, () => []).add(q);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [
          Text('行情'),
          SizedBox(width: 10),
          SessionPill(),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '選股排行',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ScreenerPage())),
          ),
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: '除權息行事曆',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ExCalendarPage())),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
          children: [
            _indexStrip(taiex),
            for (final g in groups.entries) _groupCard(g.key, g.value),
            if (_fx != null) _fxCard(),
            if (_inst.isNotEmpty) _instCard(),
            if (_hot.isNotEmpty) _hotCard(),
          ],
        ),
      ),
    );
  }

  Widget _indexStrip(IndexQuote? taiex) {
    final otc = _find('櫃買指數');
    final nas = _find('那斯達克');
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
                  onTap: taiex == null ? null : () => _openIndex(taiex),
                ),
                const _VDiv(),
                IndexCell(
                  name: '櫃買指數',
                  value: otc?.value,
                  change: otc?.change,
                  changePct: otc?.changePct,
                  onTap: otc == null ? null : () => _openIndex(otc),
                ),
                const _VDiv(),
                IndexCell(
                  name: '那斯達克',
                  value: nas?.value,
                  change: nas?.change,
                  changePct: nas?.changePct,
                  onTap: nas == null ? null : () => _openIndex(nas),
                ),
              ],
            ),
          ),
          if (_spark.length > 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SizedBox(
                height: 48,
                child: Sparkline(_spark,
                    baseline: taiex?.prevClose ?? double.nan),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupCard(String group, List<IndexQuote> list) {
    return Card(
      child: Column(
        children: [
          PanelHeader(group),
          for (final q in list) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => _openIndex(q),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 26,
                      color: q.change == null
                          ? AppColors.flat
                          : AppColors.forChange(q.change!),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text(q.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                    Text(q.value?.toStringAsFixed(2) ?? '--',
                        style: kNum.copyWith(
                            fontSize: 14,
                            color: q.change == null
                                ? AppColors.ink
                                : AppColors.forChange(q.change!))),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: Text(
                        q.change == null
                            ? '--'
                            : '${signed(q.change!, 2)}  ${q.changePct! >= 0 ? '+' : ''}${q.changePct!.toStringAsFixed(2)}%',
                        textAlign: TextAlign.right,
                        style: kNumSm.copyWith(
                            color: q.change == null
                                ? AppColors.ink3
                                : AppColors.forChange(q.change!)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _fxCard() {
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const IndexDetailPage(ySymbol: 'TWD=X', name: '美元/台幣'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                color: _fx!.change == null
                    ? AppColors.flat
                    : AppColors.forChange(_fx!.change!),
              ),
              const SizedBox(width: 9),
              const Expanded(
                  child: Text('美元 / 台幣',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              Text(_fx!.value?.toStringAsFixed(3) ?? '--',
                  style: kNum.copyWith(fontSize: 14)),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Text(
                  _fx!.change == null
                      ? '--'
                      : '${signed(_fx!.change!, 3)}  ${_fx!.changePct! >= 0 ? '+' : ''}${_fx!.changePct!.toStringAsFixed(2)}%',
                  textAlign: TextAlign.right,
                  style: kNumSm.copyWith(
                      color: _fx!.change == null
                          ? AppColors.ink3
                          : AppColors.forChange(_fx!.change!)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instCard() {
    final mx =
        _inst.map((e) => e.netYi.abs()).fold<double>(1, (a, b) => a > b ? a : b);
    return Card(
      child: Column(
        children: [
          const PanelHeader('三大法人買賣超（億元）'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Column(
              children: [
                for (final f in _inst)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(
                          width: 52,
                          child: Text(f.name,
                              style: const TextStyle(fontSize: 13))),
                      Expanded(child: DivergingBar(f.netYi, mx)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text(signed(f.netYi, 1),
                            textAlign: TextAlign.right,
                            style: kNum.copyWith(
                                fontSize: 13,
                                color: AppColors.forChange(f.netYi))),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hotCard() {
    String vol(int v) => v >= 10000
        ? '${(v / 10000).toStringAsFixed(1)}萬'
        : nf0.format(v);
    return Card(
      child: Column(
        children: [
          PanelHeader('成交量前 20',
              onMore: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ScreenerPage()))),
          for (final (i, h) in _hot.take(15).indexed) ...[
            const Divider(height: 1),
            MarketTickerRow(
              rank: i + 1,
              name: h.name,
              code: h.code,
              price: h.close,
              change: h.change,
              changePct: (h.close != null &&
                      h.change != null &&
                      (h.close! - h.change!) != 0)
                  ? h.change! / (h.close! - h.change!) * 100
                  : null,
              volumeText: vol(h.volume),
              onTap: () => _open(h.code, h.name, Market.tse),
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
