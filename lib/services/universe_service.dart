import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'api.dart';

/// 全台股清單（上市＋上櫃），供國字/代號搜尋。快取 7 天。
class UniverseService {
  List<StockRef> _all = [];
  bool _loading = false;
  static const _key = 'universe.v1';
  static const _tsKey = 'universe.ts';

  bool get ready => _all.isNotEmpty;

  Future<void> ensureLoaded() async {
    if (_all.isNotEmpty || _loading) return;
    _loading = true;
    try {
      final p = await SharedPreferences.getInstance();
      final ts = p.getInt(_tsKey) ?? 0;
      final fresh = DateTime.now().millisecondsSinceEpoch - ts <
          const Duration(days: 7).inMilliseconds;
      final cached = p.getString(_key);
      if (fresh && cached != null) {
        _all = (jsonDecode(cached) as List)
            .map((e) => StockRef(e['c'], e['n'],
                marketFromName(e['m'])))
            .toList();
        return;
      }
      final list = await _fetchAll();
      if (list.isNotEmpty) {
        _all = list;
        p.setString(
          _key,
          jsonEncode(list
              .map((s) => {'c': s.code, 'n': s.name, 'm': s.market.name})
              .toList()),
        );
        p.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
      } else if (cached != null) {
        _all = (jsonDecode(cached) as List)
            .map((e) => StockRef(e['c'], e['n'],
                marketFromName(e['m'])))
            .toList();
      }
    } catch (_) {
      /* 保持空清單，之後可再試 */
    } finally {
      _loading = false;
    }
  }

  Future<List<StockRef>> _fetchAll() async {
    final out = <StockRef>[];
    final seen = <String>{};
    try {
      final r = await webDio.get(
          'https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_AVG_ALL');
      for (final e in (r.data as List)) {
        final c = e['Code']?.toString() ?? '';
        final n = e['Name']?.toString().trim() ?? '';
        if (c.isEmpty || seen.contains('t$c')) continue;
        seen.add('t$c');
        out.add(StockRef(c, n, Market.tse));
      }
    } catch (_) {}
    try {
      final r = await webDio.get(
          'https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes');
      for (final e in (r.data as List)) {
        final c = e['SecuritiesCompanyCode']?.toString() ?? '';
        final n = e['CompanyName']?.toString().trim() ?? '';
        if (c.isEmpty || seen.contains('o$c')) continue;
        seen.add('o$c');
        out.add(StockRef(c, n, Market.otc));
      }
    } catch (_) {}
    return out;
  }

  /// 依代號前綴或名稱關鍵字搜尋
  List<StockRef> search(String q) {
    final s = q.trim();
    if (s.isEmpty) return const [];
    final byCode = <StockRef>[];
    final byName = <StockRef>[];
    for (final r in _all) {
      if (r.code.startsWith(s)) {
        byCode.add(r);
      } else if (r.name.contains(s)) {
        byName.add(r);
      }
    }
    return [...byCode, ...byName].take(40).toList();
  }

  String nameOf(String code) =>
      _all.firstWhere((r) => r.code == code,
              orElse: () => StockRef(code, code, Market.tse))
          .name;
}

final universeService = UniverseService();
