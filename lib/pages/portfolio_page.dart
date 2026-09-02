import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/financials_service.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search_page.dart';

class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(portfolioProvider);
    final quotes = ref.watch(quotesProvider);

    double cost = 0, value = 0;
    for (final p in positions) {
      final px = quotes[Symbol(p.code, p.market).id]?.price;
      cost += p.costValue;
      value += px != null ? p.marketValue(px) : p.costValue;
    }
    final pnl = value - cost;
    final pnlPct = cost == 0 ? 0.0 : pnl / cost * 100;

    return Scaffold(
      appBar: AppBar(title: const Text('持倉')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final r = await pickSymbol(context);
          if (r != null && context.mounted) {
            showAddPosition(context, ref, r.$1, r.$2);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('未實現損益',
                      style: TextStyle(color: AppColors.ink3, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    signed(pnl, 0),
                    style: kNum.copyWith(
                        fontSize: 30, color: AppColors.forChange(pnl)),
                  ),
                  Text('${signed(pnlPct, 2)}%',
                      style: kNum.copyWith(
                          fontSize: 14, color: AppColors.forChange(pnl))),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StatTile('總成本', nf0.format(cost)),
                      StatTile('總市值', nf0.format(value)),
                    ],
                  ),
                  if (positions.length > 1) ...[
                    const SizedBox(height: 16),
                    _AllocationBar(positions: positions, quotes: quotes),
                  ],
                  const SizedBox(height: 14),
                  _DividendEstimate(positions: positions),
                ],
              ),
            ),
          ),
          if (positions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: Text('尚無持倉，點右下 + 新增',
                      style: TextStyle(color: AppColors.ink3))),
            ),
          for (final p in positions)
            _posRow(context, ref, p,
                quotes[Symbol(p.code, p.market).id]?.price),
        ],
      ),
    );
  }

  Widget _posRow(
      BuildContext context, WidgetRef ref, Position p, double? px) {
    final pnl = p.pnl(px);
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.endToStart,
      background: Container(
          color: AppColors.down,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) => ref.read(portfolioProvider.notifier).remove(p.id),
      child: ListTile(
        onTap: () => showAddPosition(context, ref,
            Symbol(p.code, p.market), p.name,
            existing: p),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${p.code} · ${p.shares} 股 · 成本 ${p.cost.toStringAsFixed(2)}'
          '${px != null ? ' · 現 ${px.toStringAsFixed(2)}' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.ink3),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(signed(pnl, 0),
                style: kNum.copyWith(color: AppColors.forChange(pnl))),
            Text('${signed(p.pnlPct(px), 2)}%',
                style: kNum.copyWith(
                    fontSize: 12, color: AppColors.forChange(pnl))),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddPosition(
  BuildContext context,
  WidgetRef ref,
  Symbol s,
  String name, {
  double? price,
  Position? existing,
}) {
  final sharesC = TextEditingController(
      text: '${existing?.shares ?? (s.market == Market.us ? 1 : 1000)}');
  final start = existing?.cost ?? price ?? 100;
  final costC = TextEditingController(text: start.toStringAsFixed(2));
  // 滑桿範圍：目前價 ±50%，最少 0
  final lo = (start * 0.5).clamp(0.0, double.infinity);
  final hi = start * 1.5 + 1;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        double cost() => double.tryParse(costC.text.trim()) ?? start;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$name  ${s.code}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: sharesC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: s.market == Market.us
                      ? '股數'
                      : '股數（1 張 = 1000 股）',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (s.market != Market.us)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final q in [100, 1000, 2000, 5000])
                        ActionChip(
                          label: Text('$q'),
                          onPressed: () =>
                              setSt(() => sharesC.text = '$q'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: costC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSt(() {}),
                decoration: const InputDecoration(
                    labelText: '每股成本', border: OutlineInputBorder()),
              ),
              Slider(
                value: cost().clamp(lo, hi),
                min: lo,
                max: hi,
                divisions: 200,
                label: cost().toStringAsFixed(2),
                onChanged: (v) => setSt(() {
                  // 依價位選步進：<50 用 0.05、<500 用 0.1、其餘 1
                  final step = v < 50 ? 0.05 : (v < 500 ? 0.1 : 1.0);
                  costC.text = ((v / step).round() * step).toStringAsFixed(2);
                }),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final sh = int.tryParse(sharesC.text.trim()) ?? 0;
                  final c = cost();
                  if (sh <= 0 || c <= 0) return;
                  ref.read(portfolioProvider.notifier).upsert(Position(
                        id: s.id,
                        code: s.code,
                        market: s.market,
                        name: name,
                        shares: sh,
                        cost: c,
                      ));
                  Navigator.pop(ctx);
                },
                child: Text(existing != null ? '更新' : '加入持倉'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// 依市值的配置比例橫條
class _AllocationBar extends StatelessWidget {
  final List<Position> positions;
  final Map<String, Quote> quotes;
  const _AllocationBar({required this.positions, required this.quotes});

  static const _palette = [
    Color(0xFFFF4D4F), Color(0xFF16C784), Color(0xFF3B82F6),
    Color(0xFFF59E0B), Color(0xFFA855F7), Color(0xFF14B8A6),
    Color(0xFFEC4899), Color(0xFF84CC16),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double, Color)>[];
    double total = 0;
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final px = quotes[Symbol(p.code, p.market).id]?.price;
      final v = px != null ? p.marketValue(px) : p.costValue;
      total += v;
      rows.add((p.name, v, _palette[i % _palette.length]));
    }
    if (total <= 0) return const SizedBox();
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('配置', style: TextStyle(color: AppColors.ink3, fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              for (final r in rows)
                Expanded(
                  flex: (r.$2 / total * 1000).round().clamp(1, 1000),
                  child: Container(height: 14, color: r.$3),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final r in rows.take(6))
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, color: r.$3),
                const SizedBox(width: 4),
                Text('${r.$1} ${(r.$2 / total * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
              ]),
          ],
        ),
      ],
    );
  }
}

// 預估年配息（持股 × 近一年現金股利）
class _DividendEstimate extends StatelessWidget {
  final List<Position> positions;
  const _DividendEstimate({required this.positions});
  @override
  Widget build(BuildContext context) {
    final tw = positions.where((p) => p.market.isTW).toList();
    if (tw.isEmpty) return const SizedBox();
    return FutureBuilder<double>(
      future: () async {
        double sum = 0;
        for (final p in tw) {
          final h = await financialsService.dividendHistory(p.code, true);
          if (h.isNotEmpty) sum += h.first.cash * p.shares;
        }
        return sum;
      }(),
      builder: (c, snap) {
        if (!snap.hasData || snap.data == 0) return const SizedBox();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('預估年配息（依近一年現金股利）',
                style: TextStyle(color: AppColors.ink3, fontSize: 12)),
            Text(nf0.format(snap.data), style: kNum.copyWith(color: AppColors.up)),
          ],
        );
      },
    );
  }
}
