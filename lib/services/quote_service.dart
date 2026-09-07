import 'dart:convert';
import '../models.dart';
import 'api.dart';
import 'yahoo_service.dart';

/// 即時報價：台股走 TWSE MIS，美股走 Yahoo。
class QuoteService {
  Future<Map<String, Quote>> fetch(List<Symbol> symbols) async {
    if (symbols.isEmpty) return {};
    final tw = symbols.where((s) => s.market.isTW).toList();
    final us = symbols.where((s) => s.market == Market.us).toList();

    final out = <String, Quote>{};
    await Future.wait([
      if (tw.isNotEmpty)
        _fetchTW(tw).then((m) => out.addAll(m)),
      if (us.isNotEmpty)
        yahooService.quotes(us).then((m) => out.addAll(m)),
    ]);
    return out;
  }

  Future<Map<String, Quote>> _fetchTW(List<Symbol> symbols) async {
    final exch =
        symbols.map((s) => '${s.market.misPrefix}_${s.code}.tw').join('|');
    final byCode = <String, Map<String, dynamic>>{};
    for (var attempt = 0;
        attempt < 3 && byCode.length < symbols.length;
        attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
      final res = await misDio.get('/stock/api/getStockInfo.jsp',
          queryParameters: {
            'json': 1,
            'delay': 0,
            'ex_ch': exch,
            '_': DateTime.now().millisecondsSinceEpoch,
          });
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      final arr = (data['msgArray'] as List?) ?? const [];
      for (final m in arr) {
        final code = m['c']?.toString();
        if (code != null) byCode[code] = Map<String, dynamic>.from(m);
      }
    }
    final out = <String, Quote>{};
    for (final s in symbols) {
      final m = byCode[s.code];
      if (m != null) out[s.id] = Quote.fromMis(m);
    }

    // 有些標的（尤其債券 ETF，如 00679B）上市/上櫃分類是反的，
    // 用錯的頻道查 MIS 會回一筆沒有名稱/價格的空紀錄 → 換另一個頻道再試一次。
    final wrongMkt = symbols.where((s) {
      final q = out[s.id];
      return q == null || q.name.isEmpty || q.price == null;
    }).toList();
    if (wrongMkt.isNotEmpty) {
      final alt = wrongMkt
          .map((s) =>
              '${s.market == Market.tse ? 'otc' : 'tse'}_${s.code}.tw')
          .join('|');
      try {
        final res = await misDio.get('/stock/api/getStockInfo.jsp',
            queryParameters: {
              'json': 1,
              'delay': 0,
              'ex_ch': alt,
              '_': DateTime.now().millisecondsSinceEpoch,
            });
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        final arr = (data['msgArray'] as List?) ?? const [];
        final byCodeAlt = <String, Map<String, dynamic>>{};
        for (final m in arr) {
          final code = m['c']?.toString();
          if (code != null) byCodeAlt[code] = Map<String, dynamic>.from(m);
        }
        for (final s in wrongMkt) {
          final m = byCodeAlt[s.code];
          if (m == null) continue;
          final q = Quote.fromMis(m);
          if (q.name.isNotEmpty && q.price != null) out[s.id] = q;
        }
      } catch (_) {}
    }
    return out;
  }

  Future<Quote?> one(Symbol s) async => (await fetch([s]))[s.id];

  /// 只給台股用：判斷上市/上櫃。
  Future<Symbol?> resolve(String code) async {
    for (final mkt in [Market.tse, Market.otc]) {
      final s = Symbol(code, mkt);
      final q = await one(s);
      if (q != null && q.name.isNotEmpty) return s;
    }
    return null;
  }
}

final quoteService = QuoteService();
