import 'package:flutter/material.dart';

import '../models.dart';
import '../services/candle_service.dart';
import '../services/financials_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search_page.dart';

// Yahoo chart range 只接受這些字串（沒有 3y 這種寫法）
const _ranges = {
  '1年': '1y',
  '2年': '2y',
  '5年': '5y',
  '10年': '10y',
  '全部': 'max',
};

/// 定期定額試算：輸入標的、每期投入金額、頻率，回推歷史股價算出
/// 累積投入、目前市值、報酬率，並跟單筆全押比較。純用歷史 K 線算，
/// 不需要額外資料源。
class DcaPage extends StatefulWidget {
  final Symbol? symbol;
  final String? name;
  const DcaPage({super.key, this.symbol, this.name});
  @override
  State<DcaPage> createState() => _DcaPageState();
}

class _DcaPageState extends State<DcaPage> {
  Symbol? _symbol;
  String _name = '';
  final _amountC = TextEditingController(text: '5000');
  bool _monthly = true; // true=每月, false=每週
  int _dayOfMonth = 5; // 每月扣款日
  int _weekday = DateTime.monday; // 每週扣款日
  String _range = '5年';
  bool _withDiv = false; // 含現金股利再投入
  bool _loading = false;
  String? _err;
  _DcaResult? _result;

  @override
  void initState() {
    super.initState();
    _symbol = widget.symbol;
    _name = widget.name ?? '';
    if (_symbol != null) _calc();
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
    final amount = double.tryParse(_amountC.text.trim());
    if (s == null || amount == null || amount <= 0) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final candles = await candleService.fetch(s,
          range: _ranges[_range]!, interval: '1d');
      if (candles.length < 2) {
        setState(() {
          _err = '這檔資料不夠算（可能剛上市不久，或選的期間太長）';
          _loading = false;
        });
        return;
      }
      Map<int, double> divByYear = const {};
      if (_withDiv) {
        try {
          final hist = await financialsService.dividendHistory(
              s.code, s.market != Market.us);
          divByYear = {for (final y in hist) y.year: y.cash};
        } catch (_) {}
      }
      final result = _simulate(
          candles, amount, _monthly, _dayOfMonth, _weekday, divByYear);
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = '算不出來：$e';
        _loading = false;
      });
    }
  }

  _DcaResult _simulate(List<Candle> candles, double amount, bool monthly,
      int dayOfMonth, int weekday, Map<int, double> divByYear) {
    final start = candles.first.time;
    final end = candles.last.time;

    // 找出每期扣款的目標日期，再對應到「當天或之後最近的交易日」收盤價
    final targets = <DateTime>[];
    if (monthly) {
      var d = DateTime(start.year, start.month, dayOfMonth);
      if (d.isBefore(start)) d = DateTime(d.year, d.month + 1, dayOfMonth);
      while (!d.isAfter(end)) {
        targets.add(d);
        d = DateTime(d.year, d.month + 1, dayOfMonth);
      }
    } else {
      var d = start;
      while (d.weekday != weekday) {
        d = d.add(const Duration(days: 1));
      }
      while (!d.isAfter(end)) {
        targets.add(d);
        d = d.add(const Duration(days: 7));
      }
    }

    var ci = 0;
    double totalShares = 0, totalInvested = 0, totalDiv = 0;
    var buys = 0;
    for (final t in targets) {
      while (ci < candles.length - 1 && candles[ci].time.isBefore(t)) {
        ci++;
      }
      final px = candles[ci].close;
      if (px <= 0) continue;
      totalShares += amount / px;
      totalInvested += amount;
      buys++;
    }

    // 現金股利再投入（近似：每年 7/15 依當年持股數配息，並用當時股價買回）
    if (divByYear.isNotEmpty) {
      for (var y = start.year; y <= end.year; y++) {
        final cashPerShare = divByYear[y];
        if (cashPerShare == null || cashPerShare <= 0) continue;
        final exDay = DateTime(y, 7, 15);
        if (exDay.isBefore(start) || exDay.isAfter(end)) continue;
        var k = 0;
        while (k < candles.length - 1 && candles[k].time.isBefore(exDay)) {
          k++;
        }
        // 到這天為止已累積的持股才有配息
        double sharesByThen = 0;
        var kk = 0;
        for (final t in targets) {
          if (!t.isBefore(exDay)) break;
          while (kk < candles.length - 1 && candles[kk].time.isBefore(t)) {
            kk++;
          }
          final p = candles[kk].close;
          if (p > 0) sharesByThen += amount / p;
        }
        final divCash = sharesByThen * cashPerShare;
        final px = candles[k].close;
        if (px > 0 && divCash > 0) {
          totalShares += divCash / px;
          totalDiv += divCash;
        }
      }
    }

    final lastClose = candles.last.close;
    final value = totalShares * lastClose;

    // 單筆全押（起始日就把總投入一次買進）比較
    final lumpShares = candles.first.close > 0
        ? totalInvested / candles.first.close
        : 0.0;
    final lumpValue = lumpShares * lastClose;

    return _DcaResult(
      start: start,
      end: end,
      buys: buys,
      totalInvested: totalInvested,
      totalShares: totalShares,
      value: value,
      lumpValue: lumpValue,
      totalDiv: totalDiv,
      series: candles.map((c) => c.close).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('定期定額試算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: Text(_symbol == null ? '選擇標的' : '$_name  ${_symbol!.code}'),
            onPressed: _pick,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '每期投入金額（元）', border: OutlineInputBorder()),
            onSubmitted: (_) => _calc(),
          ),
          const SizedBox(height: 14),
          Row(children: [
            ChoiceChip(
              label: const Text('每月'),
              selected: _monthly,
              onSelected: (_) {
                setState(() => _monthly = true);
                _calc();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('每週'),
              selected: !_monthly,
              onSelected: (_) {
                setState(() => _monthly = false);
                _calc();
              },
            ),
            const SizedBox(width: 14),
            if (_monthly)
              DropdownButton<int>(
                value: _dayOfMonth,
                items: [
                  for (final d in [1, 5, 10, 15, 20, 25])
                    DropdownMenuItem(value: d, child: Text('每月 $d 號'))
                ],
                onChanged: (v) {
                  setState(() => _dayOfMonth = v!);
                  _calc();
                },
              )
            else
              DropdownButton<int>(
                value: _weekday,
                items: const [
                  DropdownMenuItem(value: DateTime.monday, child: Text('每週一')),
                  DropdownMenuItem(value: DateTime.wednesday, child: Text('每週三')),
                  DropdownMenuItem(value: DateTime.friday, child: Text('每週五')),
                ],
                onChanged: (v) {
                  setState(() => _weekday = v!);
                  _calc();
                },
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: _ranges.keys.map((k) {
              final on = k == _range;
              return ChoiceChip(
                label: Text(k),
                selected: on,
                onSelected: (_) {
                  setState(() => _range = k);
                  _calc();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('把現金股利再投入'),
            subtitle: Text('近似：每年依當年持股配息、用當時股價買回',
                style: TextStyle(fontSize: 11, color: AppColors.ink3)),
            value: _withDiv,
            onChanged: (v) {
              setState(() => _withDiv = v ?? false);
              _calc();
            },
          ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_err != null)
            Text(_err!, style: const TextStyle(color: AppColors.down)),
          if (r != null && !_loading) _resultView(r),
        ],
      ),
    );
  }

  Widget _resultView(_DcaResult r) {
    final pnl = r.value - r.totalInvested;
    final pnlPct = r.totalInvested == 0 ? 0.0 : pnl / r.totalInvested * 100;
    final lumpPnlPct = r.totalInvested == 0
        ? 0.0
        : (r.lumpValue - r.totalInvested) / r.totalInvested * 100;
    String d(DateTime t) => '${t.year}/${t.month}/${t.day}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${d(r.start)} ~ ${d(r.end)}・共扣款 ${r.buys} 次',
            style: TextStyle(fontSize: 12, color: AppColors.ink3)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: StatTile('總投入', nf0.format(r.totalInvested))),
                  Expanded(child: StatTile('目前市值', nf0.format(r.value))),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: StatTile('損益', signed(pnl, 0),
                          color: AppColors.forChange(pnl))),
                  Expanded(
                      child: StatTile('報酬率', '${signed(pnlPct, 1)}%',
                          color: AppColors.forChange(pnl))),
                ]),
                if (r.totalDiv > 0) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: StatTile(
                            '其中領到股利再投入', nf0.format(r.totalDiv),
                            color: AppColors.up)),
                  ]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 160, child: PriceLineChart(r.series)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('對照：同一筆錢起始日一次全押',
                    style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('市值 ${nf0.format(r.lumpValue)}', style: kNum),
                  Text('${signed(lumpPnlPct, 1)}%',
                      style: kNum.copyWith(
                          color: AppColors.forChange(r.lumpValue - r.totalInvested))),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('試算採歷史股價回推，未計入手續費、稅負與股利再投入，僅供參考，不是投資建議。',
            style: TextStyle(fontSize: 11, color: AppColors.ink3)),
      ],
    );
  }
}

class _DcaResult {
  final DateTime start, end;
  final int buys;
  final double totalInvested, totalShares, value, lumpValue, totalDiv;
  final List<double> series;
  _DcaResult({
    required this.start,
    required this.end,
    required this.buys,
    required this.totalInvested,
    required this.totalShares,
    required this.value,
    required this.lumpValue,
    required this.totalDiv,
    required this.series,
  });
}
