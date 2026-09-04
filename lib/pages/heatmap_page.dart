import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market_service.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

/// 成交值前幾大個股的漲跌熱力圖：格子顏色深淺 = 漲跌幅大小
class HeatmapPage extends StatefulWidget {
  const HeatmapPage({super.key});
  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  List<HeatCell> _cells = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cells = await marketService.heatmap(take: 60);
    if (!mounted) return;
    setState(() {
      _cells = cells;
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
    final up = _cells.where((c) => c.changePct > 0).length;
    final down = _cells.where((c) => c.changePct < 0).length;
    final flat = _cells.length - up - down;
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
                      Text('成交值前 ${_cells.length} 大個股',
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
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: _cells.length,
                    itemBuilder: (context, i) {
                      final c = _cells[i];
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
                  const SizedBox(height: 16),
                  const Text('格子顏色深淺代表漲跌幅大小；依成交值排序，越前面代表成交越熱絡',
                      style: TextStyle(fontSize: 11, color: AppColors.ink3)),
                ],
              ),
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
