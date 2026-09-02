import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/market_service.dart';
import '../theme.dart';
import '../widgets.dart';

const _ranges = {
  '分時': ('1d', '1m'),
  '5日': ('5d', '30m'),
  '1月': ('1mo', '1d'),
  '3月': ('3mo', '1d'),
  '1年': ('1y', '1d'),
  '5年': ('5y', '1wk'),
};

class IndexDetailPage extends StatefulWidget {
  final String ySymbol; // ^TWII、^IXIC、000001.SS…
  final String name;
  const IndexDetailPage({super.key, required this.ySymbol, required this.name});
  @override
  State<IndexDetailPage> createState() => _IndexDetailPageState();
}

class _IndexDetailPageState extends State<IndexDetailPage> {
  String _range = '1年';
  List<Candle> _data = [];
  Intraday? _intra;
  bool _loading = true;

  bool get _isIntra => _range == '分時';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (r, i) = _ranges[_range]!;
    if (_isIntra) {
      final id = await marketService.intraday(widget.ySymbol,
          range: r, interval: i);
      if (!mounted) return;
      setState(() {
        _intra = id;
        _data = id.points;
        _loading = false;
      });
    } else {
      final d = await marketService.indexHistory(widget.ySymbol,
          range: r, interval: i);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = _isIntra
        ? (_intra?.prevClose ?? (_data.isNotEmpty ? _data.first.close : null))
        : (_data.isNotEmpty ? _data.first.close : null);
    final last = _data.isNotEmpty ? _data.last.close : null;
    final chg = (base != null && last != null) ? last - base : null;
    final pct = (chg != null && base != 0) ? chg / base! * 100 : null;

    List<String> xLabels() {
      if (_data.length < 2) return const [];
      final fmt = _range == '5日'
          ? DateFormat('MM/dd HH:mm')
          : DateFormat('yyyy/MM');
      return [
        fmt.format(_data.first.time),
        fmt.format(_data[_data.length ~/ 2].time),
        fmt.format(_data.last.time),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(last?.toStringAsFixed(2) ?? '--',
                    style: kNum.copyWith(
                        fontSize: 32,
                        color: chg == null
                            ? AppColors.ink
                            : AppColors.forChange(chg))),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: ChangeText(chg, pct, size: 14),
                ),
                const Spacer(),
                Text(_isIntra ? '對昨收' : '此區間',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.ink3)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _ranges.keys.map((r) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(r),
                    selected: r == _range,
                    onSelected: (_) {
                      setState(() => _range = r);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _isIntra
                    ? IntradayChart(
                        _data.map((c) => c.close).toList(),
                        _data.map((c) => c.volume).toList(),
                        base ??
                            (_data.isNotEmpty ? _data.first.close : 0),
                        times: _data
                            .map((c) =>
                                c.time.millisecondsSinceEpoch ~/ 1000)
                            .toList(),
                        regStart: _intra?.regStart,
                        regEnd: _intra?.regEnd,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: PriceLineChart(
                          _data.map((c) => c.close).toList(),
                          xLabels: xLabels(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
