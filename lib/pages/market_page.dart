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

  @override
  Widget build(BuildContext context) {
    final taiex = _idx.where((e) => e.name == '加權指數').firstOrNull;
    final groups = <String, List<IndexQuote>>{};
    for (final q in _idx) {
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
          padding: const EdgeInsets.all(12),
          children: [
            // 加權指數大卡 + 走勢（點進看歷史）
            Card(
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => IndexDetailPage(
                        ySymbol: taiex?.ySymbol ?? '^TWII', name: '加權指數'),
                  ),
                ),
                child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: const [
                      Text('加權指數',
                          style:
                              TextStyle(color: AppColors.ink3, fontSize: 13)),
                      Spacer(),
                      Icon(Icons.chevron_right,
                          size: 18, color: AppColors.ink3),
                    ]),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          taiex?.value?.toStringAsFixed(2) ?? '--',
                          style: kNum.copyWith(
                            fontSize: 34,
                            color: taiex?.change == null
                                ? AppColors.ink
                                : AppColors.forChange(taiex!.change!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: ChangeText(taiex?.change, taiex?.changePct,
                              size: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 64,
                      child: _spark.length > 2
                          ? Sparkline(_spark,
                              baseline: taiex?.prevClose ?? double.nan)
                          : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
            ),
            // 各國指數（分組）
            for (final g in groups.entries)
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(g.key,
                            style: const TextStyle(
                                color: AppColors.ink3,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                    ),
                    for (final q in g.value)
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IndexDetailPage(
                                ySymbol: q.ySymbol, name: q.name),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(q.name),
                              Row(children: [
                                Text(q.value?.toStringAsFixed(2) ?? '--',
                                    style: kNum),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 110,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: ChangeText(q.change, q.changePct,
                                        size: 12),
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    size: 16, color: AppColors.ink3),
                              ]),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // 匯率
            if (_fx != null)
              Card(
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IndexDetailPage(
                          ySymbol: 'TWD=X', name: '美元/台幣'),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Text('美元 / 台幣'),
                        const Spacer(),
                        Text(_fx!.value?.toStringAsFixed(3) ?? '--',
                            style: kNum),
                        const SizedBox(width: 12),
                        ChangeText(_fx!.change, _fx!.changePct, size: 12),
                        const Icon(Icons.chevron_right,
                            size: 16, color: AppColors.ink3),
                      ],
                    ),
                  ),
                ),
              ),
            // 三大法人
            if (_inst.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('三大法人買賣超（億元）',
                          style:
                              TextStyle(color: AppColors.ink3, fontSize: 13)),
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final mx = _inst
                            .map((e) => e.netYi.abs())
                            .fold<double>(1, (a, b) => a > b ? a : b);
                        return Column(
                          children: [
                            for (final f in _inst)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6),
                                child: Row(children: [
                                  SizedBox(
                                      width: 52,
                                      child: Text(f.name,
                                          style:
                                              const TextStyle(fontSize: 13))),
                                  Expanded(
                                      child: DivergingBar(f.netYi, mx)),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 62,
                                    child: Text(signed(f.netYi, 1),
                                        textAlign: TextAlign.right,
                                        style: kNum.copyWith(
                                            fontSize: 13,
                                            color: AppColors.forChange(
                                                f.netYi))),
                                  ),
                                ]),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            // 熱門股
            if (_hot.isNotEmpty)
              Card(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('成交量前 20',
                            style: TextStyle(
                                color: AppColors.ink3, fontSize: 13)),
                      ),
                    ),
                    for (final h in _hot.take(12))
                      ListTile(
                        dense: true,
                        title: Text('${h.name}  ${h.code}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(h.close?.toStringAsFixed(2) ?? '--',
                                style: kNum),
                            const SizedBox(width: 10),
                            Text(signed(h.change ?? 0, 2),
                                style: kNum.copyWith(
                                    fontSize: 12,
                                    color: AppColors.forChange(
                                        h.change ?? 0))),
                          ],
                        ),
                        onTap: () => _open(h.code, h.name, Market.tse),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
