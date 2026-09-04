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
        'events': 'split', // 用來還原 Yahoo 的減資/合股/分割調整
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

    // Yahoo 對台股會把「分割/減資」前的價格往回除，讓圖連續，但這樣舊資料
    // 就跟 MIS 即時價（未還原）對不起來。這裡把那個調整乘回去，讓整條線
    // 跟報價、跟其他券商 App 一致。
    final splits = <(int date, double ratio)>[];
    final ev = r['events'];
    if (ev is Map && ev['splits'] is Map) {
      for (final v in (ev['splits'] as Map).values) {
        if (v is! Map) continue;
        final numer = (v['numerator'] as num?)?.toDouble();
        final den = (v['denominator'] as num?)?.toDouble();
        final date = (v['date'] as num?)?.toInt();
        if (numer != null && den != null && den != 0 && date != null) {
          splits.add((date, numer / den));
        }
      }
      splits.sort((a, b) => a.$1.compareTo(b.$1));
    }
    double factorFor(int tsSec) {
      var f = 1.0;
      for (final sp in splits) {
        if (sp.$1 > tsSec) f *= sp.$2;
      }
      return f;
    }

    final out = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      final o = open.length > i ? open[i] : null;
      final h = high.length > i ? high[i] : null;
      final l = low.length > i ? low[i] : null;
      final c = close.length > i ? close[i] : null;
      if (o == null || h == null || l == null || c == null) continue;
      final f = splits.isEmpty ? 1.0 : factorFor(ts[i]);
      out.add(Candle(
        DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000),
        (o as num).toDouble() * f,
        (h as num).toDouble() * f,
        (l as num).toDouble() * f,
        (c as num).toDouble() * f,
        vol.length > i && vol[i] != null ? (vol[i] as num).toDouble() : 0,
      ));
    }
    return out;
  }
}

final candleService = CandleService();
