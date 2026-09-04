import 'package:flutter/material.dart';

import '../models.dart';
import '../services/candle_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search_page.dart';

const _kCompareColors = [
  AppColors.accent,
  AppColors.warn,
  Color(0xFF8B5CF6), // 紫
];

const _kRanges = {
  '1月': ('1mo', '1d'),
  '3月': ('3mo', '1d'),
  '半年': ('6mo', '1d'),
  '1年': ('1y', '1d'),
};

class ComparePage extends StatefulWidget {
  final Symbol base;
  final String baseName;
  const ComparePage({super.key, required this.base, required this.baseName});
  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  late final List<(Symbol, String)> _picks = [(widget.base, widget.baseName)];
  String _range = '3月';
  bool _loading = true;
  List<CompareSeries> _series = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (range, interval) = _kRanges[_range]!;
    final out = <CompareSeries>[];
    for (var i = 0; i < _picks.length; i++) {
      final (sym, name) = _picks[i];
      try {
        final candles =
            await candleService.fetch(sym, range: range, interval: interval);
        if (candles.length < 2) continue;
        final base0 = candles.first.close;
        final pct = candles
            .map((c) => base0 == 0 ? 0.0 : (c.close / base0 - 1) * 100)
            .toList();
        out.add(CompareSeries(name, _kCompareColors[i % 3], pct));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _series = out;
      _loading = false;
    });
  }

  Future<void> _addPick() async {
    if (_picks.length >= 3) return;
    final r = await pickSymbol(context);
    if (r == null) return;
    final (sym, name) = r;
    if (_picks.any((p) => p.$1 == sym)) return;
    setState(() => _picks.add((sym, name)));
    _load();
  }

  void _remove(int i) {
    if (i == 0) return; // 主標的不能移除
    setState(() => _picks.removeAt(i));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('個股比較')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Wrap(
              spacing: 6,
              children: _kRanges.keys.map((r) {
                final on = r == _range;
                return ChoiceChip(
                  label: Text(r),
                  selected: on,
                  onSelected: (_) {
                    setState(() => _range = r);
                    _load();
                  },
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _picks.length; i++)
                  Chip(
                    avatar: CircleAvatar(
                        backgroundColor: _kCompareColors[i % 3],
                        radius: 6),
                    label: Text(_picks[i].$2),
                    onDeleted: i == 0 ? null : () => _remove(i),
                  ),
                if (_picks.length < 3)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('加入比較'),
                    onPressed: _addPick,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CompareChart(_series),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('以區間第一天收盤為 0% 基準比較漲跌幅',
                style: TextStyle(fontSize: 11, color: AppColors.ink3)),
          ),
        ],
      ),
    );
  }
}
