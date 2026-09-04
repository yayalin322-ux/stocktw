import 'package:flutter/material.dart';

import '../models.dart';
import '../services/financials_service.dart';
import '../services/market_service.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

/// 成交值前幾大個股的漲跌熱力圖，依產業族群分組（電子細分成半導體／
/// 光電／通信網路／電子零組件…等 TWSE 自己的分類，不是籠統一包）
class HeatmapPage extends StatefulWidget {
  const HeatmapPage({super.key});
  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  Map<String, List<HeatCell>> _groups = {};
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cells = await marketService.heatmap(take: 90);
    await financialsService.ensureProfiles();
    final groups = <String, List<HeatCell>>{};
    for (final c in cells) {
      final ind = financialsService.industryOf(c.code) ?? '其他';
      groups.putIfAbsent(ind, () => []).add(c);
    }
    for (final l in groups.values) {
      l.sort((a, b) => b.turnoverYi.compareTo(a.turnoverYi));
    }
    // 族群依組內總成交值排序，熱門的排前面
    final order = groups.entries.toList()
      ..sort((a, b) =>
          b.value.fold<double>(0, (s, e) => s + e.turnoverYi).compareTo(
              a.value.fold<double>(0, (s, e) => s + e.turnoverYi)));
    if (!mounted) return;
    setState(() {
      _groups = {for (final e in order) e.key: e.value};
      _total = cells.length;
      _loading = false;
    });
  }

  // 漲跌幅換算成顏色深淺：0~7% 對應到 alpha 0.2~1.0
  Color _colorFor(double pct) {
    final base = pct >= 0 ? AppColors.up : AppColors.down;
    final a = 0.22 + (pct.abs() / 7).clamp(0.0, 1.0) * 0.78;
    return base.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final all = _groups.values.expand((e) => e);
    final up = all.where((c) => c.changePct > 0).length;
    final down = all.where((c) => c.changePct < 0).length;
    final flat = _total - up - down;
    return Scaffold(
      appBar: AppBar(title: const Text('熱力圖')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Text('成交值前 $_total 大個股・依產業分組',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink3)),
                      const Spacer(),
                      _dot(AppColors.up, '$up 漲'),
                      const SizedBox(width: 10),
                      _dot(AppColors.ink3, '$flat 平'),
                      const SizedBox(width: 10),
                      _dot(AppColors.down, '$down 跌'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final e in _groups.entries) _groupSection(e.key, e.value),
                  const SizedBox(height: 8),
                  const Text('格子顏色深淺代表漲跌幅大小；族群跟個股都依成交值排序',
                      style: TextStyle(fontSize: 11, color: AppColors.ink3)),
                ],
              ),
            ),
    );
  }

  Widget _groupSection(String industry, List<HeatCell> cells) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                  color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 7),
            Text(industry,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('${cells.length} 檔',
                style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
          ]),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.95,
            ),
            itemCount: cells.length,
            itemBuilder: (context, i) {
              final c = cells[i];
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuoteDetailPage(
                      symbol: Symbol(c.code, Market.tse),
                      name: c.name,
                    ),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: _colorFor(c.changePct),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(4),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          '${c.changePct >= 0 ? '+' : ''}${c.changePct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
      ]);
}
