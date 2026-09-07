import 'package:flutter/material.dart';

import '../models.dart';
import '../services/financials_service.dart';
import '../theme.dart';
import 'search_page.dart';

/// 股票股利／除權息換算：選股票、輸入持有股數，換算會領到多少現金、配到幾股。
/// 「配息/配股 元/股」的數字不好想，這裡直接算成實際金額與股數。
class DividendCalcPage extends StatefulWidget {
  final Symbol? symbol;
  final String? name;
  const DividendCalcPage({super.key, this.symbol, this.name});
  @override
  State<DividendCalcPage> createState() => _DividendCalcPageState();
}

class _DividendCalcPageState extends State<DividendCalcPage> {
  Symbol? _symbol;
  String _name = '';
  final _sharesC = TextEditingController(text: '1000');
  final _cashC = TextEditingController(); // 現金股利 元/股（可手動）
  final _stockC = TextEditingController(); // 股票股利 元/股（可手動）
  double? _refPrice;
  String? _period;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _symbol = widget.symbol;
    _name = widget.name ?? '';
    if (_symbol != null) _fetch();
  }

  Future<void> _pick() async {
    final r = await pickSymbol(context);
    if (r == null) return;
    setState(() {
      _symbol = r.$1;
      _name = r.$2;
    });
    _fetch();
  }

  Future<void> _fetch() async {
    final s = _symbol;
    if (s == null) return;
    setState(() => _loading = true);
    try {
      final rows = await financialsService.dividends(s.code);
      if (rows.isNotEmpty) {
        final r = rows.first;
        _cashC.text = r.cash.toStringAsFixed(2);
        _stockC.text = r.stock.toStringAsFixed(2);
        _period = '${r.year} 年${r.period.isNotEmpty ? '（${r.period}）' : ''}';
      }
      final ex = await financialsService.exDividend(s.code);
      _refPrice = ex?.refPrice;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final shares = double.tryParse(_sharesC.text.trim()) ?? 0;
    final cash = double.tryParse(_cashC.text.trim()) ?? 0;
    final stock = double.tryParse(_stockC.text.trim()) ?? 0;
    final cashAmount = shares * cash;
    final bonusShares = shares * stock / 10; // 面額 10 元
    final afterShares = shares + bonusShares;

    return Scaffold(
      appBar: AppBar(title: const Text('股利／除權息換算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: Text(_symbol == null
                ? '選擇股票（可略過，直接手動輸入）'
                : '$_name  ${_symbol!.code}'),
            onPressed: _pick,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_period != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('已帶入 $_period 董事會決議配發',
                  style: TextStyle(fontSize: 12, color: AppColors.ink3)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _sharesC,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: '持有股數（1 張 = 1000 股）',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cashC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: '現金股利（元/股）',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _stockC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: '股票股利（元/股）',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('領到現金股利', '${_nf(cashAmount)} 元',
                      big: true, color: AppColors.up),
                  const Divider(height: 22),
                  _row('配到股票股數', '${_nf(bonusShares)} 股'),
                  _row('約當', '${(bonusShares / 1000).toStringAsFixed(2)} 張'),
                  const Divider(height: 22),
                  _row('除權息後總股數', '${_nf(afterShares)} 股'),
                  if (_refPrice != null && _refPrice! > 0)
                    _row('除權息參考價', '${_refPrice!.toStringAsFixed(2)} 元'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '股票股利以「元/股」表示、面額 10 元，故配股數 = 股數 × 股票股利 ÷ 10。'
            '未計入二代健保補充保費、股利所得稅。實際以公司公告與集保為準。',
            style: TextStyle(fontSize: 11, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  String _nf(double v) => v
      .toStringAsFixed(v.abs() < 100 ? 2 : 0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Widget _row(String k, String v, {bool big = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: big ? 14 : 13, color: AppColors.ink2)),
          Text(v,
              style: TextStyle(
                  fontSize: big ? 20 : 15,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.ink)),
        ],
      ),
    );
  }
}
