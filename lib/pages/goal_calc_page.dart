import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/candle_service.dart';
import '../theme.dart';
import 'search_page.dart';

/// 目標金額試算：想存到多少錢、存幾年，用某檔 ETF／個股的歷史年化報酬率
/// 回推「需要一次投入多少」或「每月需要投入多少」。
class GoalCalcPage extends StatefulWidget {
  const GoalCalcPage({super.key});
  @override
  State<GoalCalcPage> createState() => _GoalCalcPageState();
}

class _GoalCalcPageState extends State<GoalCalcPage> {
  Symbol? _symbol;
  String _name = '';
  final _targetC = TextEditingController(text: '1000000');
  int _years = 10;
  bool _loading = false;
  String? _err;
  double? _cagr; // 年化報酬率
  double? _spanYears; // 實際回看年數

  @override
  void initState() {
    super.initState();
    // 預設 0050
    _symbol = const Symbol('0050', Market.tse);
    _name = '元大台灣50';
    _calc();
  }

  Future<void> _pick() async {
    final r = await pickSymbol(context);
    if (r == null) return;
    setState(() {
      _symbol = r.$1;
      _name = r.$2;
    });
    _calc();
  }

  Future<void> _calc() async {
    final s = _symbol;
    if (s == null) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final candles =
          await candleService.fetch(s, range: '10y', interval: '1mo');
      if (candles.length < 24) {
        setState(() {
          _err = '這檔歷史資料不夠（至少要 2 年），換一檔或選上市較久的 ETF';
          _loading = false;
        });
        return;
      }
      final first = candles.first;
      final last = candles.last;
      final span = last.time.difference(first.time).inDays / 365.25;
      final cagr = math.pow(last.close / first.close, 1 / span) - 1.0;
      setState(() {
        _cagr = cagr.toDouble();
        _spanYears = span;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = '算不出來：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(_targetC.text.trim()) ?? 0;
    final cagr = _cagr;
    double? lump, monthly;
    if (cagr != null && target > 0) {
      final n = _years * 12;
      final r = math.pow(1 + cagr, 1 / 12) - 1.0;
      lump = target / math.pow(1 + cagr, _years);
      if (r.abs() < 1e-9) {
        monthly = target / n;
      } else {
        final factor = (math.pow(1 + r, n) - 1) / r;
        monthly = target / factor;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('目標金額試算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: Text(_symbol == null
                ? '選擇標的'
                : '$_name  ${_symbol!.code}'),
            onPressed: _pick,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _targetC,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: '目標金額（元）', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Text('存 ', style: TextStyle(color: AppColors.ink2)),
            Expanded(
              child: Slider(
                min: 1,
                max: 40,
                divisions: 39,
                label: '$_years 年',
                value: _years.toDouble(),
                onChanged: (v) => setState(() => _years = v.round()),
              ),
            ),
            Text(' $_years 年',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_err != null)
            Text(_err!, style: const TextStyle(color: AppColors.down)),
          if (cagr != null && !_loading) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '$_name 近 ${_spanYears!.toStringAsFixed(1)} 年'
                        '年化報酬率約 ${(cagr * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.ink3)),
                    const Divider(height: 22),
                    _big('一次投入需要', lump),
                    const SizedBox(height: 14),
                    _big('或每月投入需要', monthly),
                    const SizedBox(height: 6),
                    Text('（$_years 年後合計約 ${_nf((monthly ?? 0) * _years * 12)} 元本金）',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.ink3)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '以過去 ${_spanYears!.toStringAsFixed(0)} 年的年化報酬率推估未來，'
              '未來實際報酬可能更高或更低、甚至虧損；未計入手續費、稅負、通膨。'
              '僅供試算參考，不是投資建議。',
              style: TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ],
        ],
      ),
    );
  }

  String _nf(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Widget _big(String k, double? v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(k, style: TextStyle(fontSize: 14, color: AppColors.ink2)),
        Text(v == null ? '--' : '${_nf(v)} 元',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
