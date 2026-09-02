import '../models.dart';
import 'api.dart';

/// Yahoo Finance：美股（及其他非台股）報價與搜尋
class YahooService {
  Future<Quote?> quote(Symbol s) async {
    try {
      final sym = '${s.code}${s.market.yahooSuffix}';
      final res = await yahooDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/$sym',
        queryParameters: {'range': '1d', 'interval': '1d'},
      );
      final m = res.data['chart']?['result']?[0]?['meta'];
      if (m == null) return null;
      double? d(v) => (v is num) ? v.toDouble() : null;
      return Quote(
        code: s.code,
        name: (m['shortName'] ?? m['longName'] ?? s.code).toString(),
        price: d(m['regularMarketPrice']),
        prevClose: d(m['chartPreviousClose']) ?? d(m['previousClose']),
        open: d(m['regularMarketOpen']),
        high: d(m['regularMarketDayHigh']),
        low: d(m['regularMarketDayLow']),
        volume: (m['regularMarketVolume'] is num)
            ? (m['regularMarketVolume'] as num).toInt()
            : 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Quote>> quotes(List<Symbol> symbols) async {
    final out = <String, Quote>{};
    await Future.wait(symbols.map((s) async {
      final q = await quote(s);
      if (q != null) out[s.id] = q;
    }));
    return out;
  }

  /// 美股搜尋（代號或公司名）
  Future<List<StockRef>> search(String q) async {
    try {
      final res = await yahooDio.get(
        'https://query2.finance.yahoo.com/v1/finance/search',
        queryParameters: {'q': q, 'quotesCount': 15, 'newsCount': 0},
      );
      final quotes = (res.data['quotes'] as List?) ?? const [];
      final usEx = {'NMS', 'NYQ', 'NGM', 'PCX', 'ASE', 'BATS'};
      return quotes
          .where((e) =>
              e['quoteType'] == 'EQUITY' &&
              usEx.contains(e['exchange']?.toString()))
          .map((e) => StockRef(
                e['symbol'].toString(),
                (e['shortname'] ?? e['longname'] ?? e['symbol']).toString(),
                Market.us,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

final yahooService = YahooService();
