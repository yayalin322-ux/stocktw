import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'api.dart';

double? _d(dynamic v) {
  final s = v?.toString().replaceAll(',', '').trim();
  if (s == null || s.isEmpty) return null;
  return double.tryParse(s);
}

const industryMap = {
  '01': '水泥', '02': '食品', '03': '塑膠', '04': '紡織纖維',
  '05': '電機機械', '06': '電器電纜', '08': '玻璃陶瓷', '09': '造紙',
  '10': '鋼鐵', '11': '橡膠', '12': '汽車', '14': '建材營造',
  '15': '航運', '16': '觀光餐旅', '17': '金融保險', '18': '貿易百貨',
  '20': '其他', '21': '化學工業', '22': '生技醫療', '23': '油電燃氣',
  '24': '半導體', '25': '電腦及週邊設備', '26': '光電', '27': '通信網路',
  '28': '電子零組件', '29': '電子通路', '30': '資訊服務', '31': '其他電子',
  '32': '文化創意', '33': '農業科技', '34': '電子商務', '35': '綠能環保',
  '36': '數位雲端', '37': '運動休閒', '38': '居家生活',
};

class Revenue {
  final String ym; // 資料年月 e.g. 11507
  final double month; // 當月營收（千）
  final double? yoy; // 去年同月增減 %
  final double? accYoy; // 累計年增 %
  Revenue(this.ym, this.month, this.yoy, this.accYoy);
}

class Income {
  final String period; // e.g. 115 Q2
  final double? revenue, grossProfit, opIncome, netIncome, eps;
  Income(this.period,
      {this.revenue, this.grossProfit, this.opIncome, this.netIncome, this.eps});
  double? get grossMargin =>
      (revenue ?? 0) != 0 && grossProfit != null ? grossProfit! / revenue! * 100 : null;
  double? get netMargin =>
      (revenue ?? 0) != 0 && netIncome != null ? netIncome! / revenue! * 100 : null;
}

class DividendRow {
  final String year; // 股利年度
  final String period; // 所屬年(季)度
  final String progress; // 決議進度
  final double cash; // 現金股利 元/股
  final double stock; // 股票股利 元/股
  final String agmDate; // 股東會日期
  DividendRow(this.year, this.period, this.progress, this.cash, this.stock,
      this.agmDate);
}

class Profile {
  final String? industry, chairman, ceo, listedDate, foundedDate, site;
  final double? capital; // 實收資本額（元）
  Profile(
      {this.industry,
      this.chairman,
      this.ceo,
      this.listedDate,
      this.foundedDate,
      this.site,
      this.capital});
}

/// 即將除權息
class ExDividend {
  final String exDate; // 除權除息日期（民國）
  final String kind; // 權 / 息 / 權息
  final double cash; // 現金股利 元/股
  final double stockRate; // 無償配股率
  final double? refPrice; // 參考價試算
  ExDividend(this.exDate, this.kind, this.cash, this.stockRate, this.refPrice);
}

/// 某一年的現金股利合計
class YearDividend {
  final int year;
  final double cash;
  YearDividend(this.year, this.cash);
}

/// 融資融券
class MarginInfo {
  final double financeBal; // 融資今日餘額（張）
  final double financeChg; // 較前日
  final double shortBal; // 融券今日餘額（張）
  final double shortChg;
  MarginInfo(this.financeBal, this.financeChg, this.shortBal, this.shortChg);
  double get shortRatio =>
      financeBal == 0 ? 0 : shortBal / financeBal * 100; // 券資比 %
}

class FinancialsService {
  List<dynamic>? _rev, _inc, _div, _prof;
  DateTime? _at;

  Future<void> _ensure() async {
    if (_at != null && DateTime.now().difference(_at!) < const Duration(hours: 6)) {
      return;
    }
    Future<List<dynamic>?> g(String url) async {
      try {
        final r = await webDio.get(url,
            options: Options(responseType: ResponseType.json));
        return r.data is String ? jsonDecode(r.data) as List : r.data as List;
      } catch (_) {
        return null;
      }
    }

    _rev = await g('https://openapi.twse.com.tw/v1/opendata/t187ap05_L');
    _inc = await g('https://openapi.twse.com.tw/v1/opendata/t187ap06_L_ci');
    _div = await g('https://openapi.twse.com.tw/v1/opendata/t187ap45_L');
    _prof = await g('https://openapi.twse.com.tw/v1/opendata/t187ap03_L');
    _at = DateTime.now();
  }

  Future<Revenue?> revenue(String code) async {
    await _ensure();
    final e = _rev?.cast<Map>().firstWhere((x) => x['公司代號'] == code,
        orElse: () => {});
    if (e == null || e.isEmpty) return null;
    return Revenue(
      e['資料年月']?.toString() ?? '',
      _d(e['營業收入-當月營收']) ?? 0,
      _d(e['營業收入-去年同月增減(%)']),
      _d(e['累計營業收入-前期比較增減(%)']),
    );
  }

  Future<Income?> income(String code) async {
    await _ensure();
    final e = _inc?.cast<Map>().firstWhere((x) => x['公司代號'] == code,
        orElse: () => {});
    if (e == null || e.isEmpty) return null;
    return Income(
      '${e['年度']} Q${e['季別']}',
      revenue: _d(e['營業收入']),
      grossProfit: _d(e['營業毛利（毛損）']),
      opIncome: _d(e['營業利益（損失）']),
      netIncome: _d(e['本期淨利（淨損）']),
      eps: _d(e['基本每股盈餘（元）']),
    );
  }

  Future<List<DividendRow>> dividends(String code) async {
    await _ensure();
    final rows = _div?.cast<Map>().where((x) => x['公司代號'] == code) ?? const [];
    return rows.map((e) {
      final cash = (_d(e['股東配發-盈餘分配之現金股利(元/股)']) ?? 0) +
          (_d(e['股東配發-資本公積發放之現金(元/股)']) ?? 0);
      final stock = (_d(e['股東配發-盈餘轉增資配股(元/股)']) ?? 0) +
          (_d(e['股東配發-法定盈餘公積轉增資配股(元/股)']) ?? 0) +
          (_d(e['股東配發-資本公積轉增資配股(元/股)']) ?? 0);
      return DividendRow(
        e['股利年度']?.toString() ?? '',
        e['股利所屬年(季)度']?.toString() ?? '',
        e['決議（擬議）進度']?.toString() ?? '',
        cash,
        stock,
        e['股東會日期']?.toString() ?? '',
      );
    }).toList();
  }

  List<dynamic>? _exList;
  DateTime? _exAt;

  /// 即將除權息（TWSE 除權除息預告表）
  Future<ExDividend?> exDividend(String code) async {
    if (_exAt == null ||
        DateTime.now().difference(_exAt!) > const Duration(hours: 6)) {
      try {
        final r = await webDio.get(
          'https://www.twse.com.tw/rwd/zh/exRight/TWT48U',
          queryParameters: {'response': 'json'},
          options: Options(responseType: ResponseType.json),
        );
        final j = r.data is Map ? r.data as Map : {};
        _exList = j['stat'] == 'OK' ? (j['data'] as List) : null;
      } catch (_) {
        _exList = null;
      }
      _exAt = DateTime.now();
    }
    try {
      final row = _exList?.cast<List>().firstWhere(
            (e) => e.length > 1 && e[1].toString().trim() == code,
            orElse: () => const [],
          );
      if (row == null || row.length < 8) return null;
      String at(int i) => i < row.length ? row[i].toString() : '';
      return ExDividend(
        at(0),
        at(3),
        _d(at(7)) ?? 0,
        _d(at(4)) ?? 0,
        _d(at(9)),
      );
    } catch (_) {
      return null;
    }
  }

  /// 現金股利歷史（Yahoo 股利事件，依年彙總）
  Future<List<YearDividend>> dividendHistory(String code, bool tw) async {
    try {
      final sym = tw ? '$code.TW' : code;
      final r = await webDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/$sym',
        queryParameters: {'range': '10y', 'interval': '1mo', 'events': 'div'},
      );
      final ev = r.data['chart']?['result']?[0]?['events']?['dividends']
          as Map<String, dynamic>?;
      if (ev == null) return const [];
      final byYear = <int, double>{};
      for (final v in ev.values) {
        final ts = (v['date'] as num).toInt();
        final y = DateTime.fromMillisecondsSinceEpoch(ts * 1000).year;
        byYear[y] = (byYear[y] ?? 0) + ((v['amount'] as num).toDouble());
      }
      final out = byYear.entries.map((e) => YearDividend(e.key, e.value)).toList()
        ..sort((a, b) => b.year.compareTo(a.year));
      return out.take(8).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, List<String>>? _margin;
  DateTime? _marginAt;

  /// 融資融券（MI_MARGN 融資融券彙總，往回找交易日）
  Future<MarginInfo?> margin(String code) async {
    if (_marginAt == null ||
        DateTime.now().difference(_marginAt!) > const Duration(hours: 3)) {
      final fmt = DateFormat('yyyyMMdd');
      for (var i = 0; i < 6; i++) {
        try {
          final d = DateTime.now().subtract(Duration(days: i));
          final r = await webDio.get(
            'https://www.twse.com.tw/rwd/zh/marginTrading/MI_MARGN',
            queryParameters: {
              'response': 'json',
              'date': fmt.format(d),
              'selectType': 'ALL',
            },
            options: Options(responseType: ResponseType.json),
          );
          final j = r.data is Map ? r.data as Map : {};
          if (j['stat'] != 'OK') continue;
          final tables = (j['tables'] as List?) ?? const [];
          final sum = tables.cast<Map>().firstWhere(
                (t) => (t['title'] as String).contains('彙總'),
                orElse: () => {},
              );
          final rows = (sum['data'] as List?)?.cast<List>() ?? const [];
          _margin = {for (final row in rows) row[0].toString(): row.cast<String>()};
          break;
        } catch (_) {}
      }
      _marginAt = DateTime.now();
    }
    final r = _margin?[code];
    if (r == null) return null;
    // fields: 0代號 1名稱 2買 3賣 4現償 5前日 6今日 7限額 | 8券買 9券賣 10券償 11前日 12今日
    final fb = _d(r[6]) ?? 0, fp = _d(r[5]) ?? 0;
    final sb = _d(r[12]) ?? 0, sp = _d(r[11]) ?? 0;
    return MarginInfo(fb, fb - fp, sb, sb - sp);
  }

  Future<Profile?> profile(String code) async {
    await _ensure();
    final e = _prof?.cast<Map>().firstWhere((x) => x['公司代號'] == code,
        orElse: () => {});
    if (e == null || e.isEmpty) return null;
    final ind = e['產業別']?.toString();
    return Profile(
      industry: industryMap[ind] ?? ind,
      chairman: e['董事長']?.toString(),
      ceo: e['總經理']?.toString(),
      listedDate: e['上市日期']?.toString(),
      foundedDate: e['成立日期']?.toString(),
      site: e['網址']?.toString(),
      capital: _d(e['實收資本額']),
    );
  }

  /// 確保公司基本資料（含產業別）已載入，給批次查產業別用
  Future<void> ensureProfiles() => _ensure();

  /// 同步查產業別（要先呼叫過 ensureProfiles/profile 讓資料就緒）
  String? industryOf(String code) {
    final e = _prof?.cast<Map>().firstWhere((x) => x['公司代號'] == code,
        orElse: () => {});
    if (e == null || e.isEmpty) return null;
    final ind = e['產業別']?.toString();
    return industryMap[ind] ?? ind;
  }
}

final financialsService = FinancialsService();
