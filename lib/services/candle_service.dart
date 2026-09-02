import '../models.dart';
import 'api.dart';

/// K 線資料（Yahoo Finance chart API，免金鑰）
class CandleService {
  /// range 例：1mo 3mo 6mo 1y 2y 5y max；interval 例：1d 1wk 1mo 5m 15m 60m
  Future<List<Candle>> fetch(
    Symbol s, {
    String range = '1y',
    String interval = '1d',
  }) async {
    final sym = '${s.code}${s.market.yahooSuffix}';
    final res = await yahooDio.get(
      'https://query1.finance.yahoo.com/v8/finance/chart/$sym',
      queryParameters: {
        'range': range,
        'interval': interval,
        'includePrePost': false,
      },
    );
    final result = res.data['chart']?['result'];
    if (result == null || (result as List).isEmpty) return [];
    final r = result[0];
    final ts = (r['timestamp'] as List?)?.cast<int>() ?? const [];
    final q = r['indicators']?['quote']?[0];
    if (q == null) return [];
    final open = (q['open'] as List?) ?? const [];
    final high = (q['high'] as List?) ?? const [];
    final low = (q['low'] as List?) ?? const [];
    final close = (q['close'] as List?) ?? const [];
    final vol = (q['volume'] as List?) ?? const [];

    final out = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      final o = open.length > i ? open[i] : null;
      final h = high.length > i ? high[i] : null;
      final l = low.length > i ? low[i] : null;
      final c = close.length > i ? close[i] : null;
      if (o == null || h == null || l == null || c == null) continue;
      out.add(Candle(
        DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000),
        (o as num).toDouble(),
        (h as num).toDouble(),
        (l as num).toDouble(),
        (c as num).toDouble(),
        vol.length > i && vol[i] != null ? (vol[i] as num).toDouble() : 0,
      ));
    }
    return out;
  }
}

final candleService = CandleService();
