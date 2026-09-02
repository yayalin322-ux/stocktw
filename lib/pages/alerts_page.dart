import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'search_page.dart';

class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final quotes = ref.watch(quotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('到價提醒')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final r = await pickSymbol(context);
          if (r != null && context.mounted) {
            showAddAlert(context, ref, r.$1, r.$2);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: alerts.isEmpty
          ? const Center(
              child: Text('尚無提醒，點右下 + 新增',
                  style: TextStyle(color: AppColors.ink3)))
          : ListView.separated(
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = alerts[i];
                final px = quotes[Symbol(a.code, a.market).id]?.price;
                final c = a.above ? AppColors.up : AppColors.down;
                return Dismissible(
                  key: ValueKey(a.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                      color: AppColors.down,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) =>
                      ref.read(alertsProvider.notifier).remove(a.id),
                  child: ListTile(
                    leading: Icon(
                      a.triggered
                          ? Icons.check_circle
                          : (a.above
                              ? Icons.trending_up
                              : Icons.trending_down),
                      color: a.triggered ? AppColors.ink3 : c,
                    ),
                    title: Text('${a.name}  ${a.code}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${a.above ? '漲到' : '跌到'} ${a.target.toStringAsFixed(2)}'
                      '${px != null ? '   現價 ${px.toStringAsFixed(2)}' : ''}'
                      '${a.triggered ? '   ✓ 已觸發' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                    ),
                    trailing: a.triggered
                        ? TextButton(
                            onPressed: () {
                              final next = [
                                for (final x in alerts)
                                  if (x.id == a.id)
                                    PriceAlert(
                                      id: x.id,
                                      code: x.code,
                                      market: x.market,
                                      name: x.name,
                                      target: x.target,
                                      above: x.above,
                                    )
                                  else
                                    x
                              ];
                              ref.read(alertsProvider.notifier).update(next);
                            },
                            child: const Text('重設'),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}

Future<void> showAddAlert(
  BuildContext context,
  WidgetRef ref,
  Symbol s,
  String name, {
  double? price,
}) {
  final ctrl = TextEditingController(text: price?.toStringAsFixed(2) ?? '');
  bool above = true;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$name  ${s.code}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('漲到'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: false, label: Text('跌到'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {above},
              onSelectionChanged: (v) => setSt(() => above = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '目標價', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final t = double.tryParse(ctrl.text.trim()) ?? 0;
                if (t <= 0) return;
                ref.read(alertsProvider.notifier).add(PriceAlert(
                      id: '${s.id}:${DateTime.now().millisecondsSinceEpoch}',
                      code: s.code,
                      market: s.market,
                      name: name,
                      target: t,
                      above: above,
                    ));
                Navigator.pop(ctx);
              },
              child: const Text('建立提醒'),
            ),
          ],
        ),
      ),
    ),
  );
}
