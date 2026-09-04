import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'api.dart';

class IndexQuote {
  final String group; // 台股 / 美股 / 亞洲
  final String name;
  final String ySymbol; // Yahoo 代號，供歷史圖用（^TWII、^IXIC、000001.SS…）
  final double? value;
  final double? prevClose;
  IndexQuote(this.group, this.name, this.ySymbol, this.value, this.prevClose);
  double? get change =>
      (value != null && prevClose != null) ? value! - prevClose! : null;
  double? get changePct => (change != null && (prevClose ?? 0) != 0)
      ? change! / prevClose! * 100
      : null;
}

class InstFlow {
  final String name;
  final double netYi;
  InstFlow(this.name, this.netYi);
}

class HotStock {
  final String code;
  final String name;
  final double? close;
  final double? change;
  final int volume;
  HotStock(this.code, this.name, this.close, this.change, this.volume);
}

class NewsHead {
  final String title;
  final String url;
  NewsHead(this.title, this.url);
}

class Intraday {
  final List<Candle> points;
  final int? regStart; // 正常盤 epoch 秒
  final int? regEnd;
  final double? prevClose;
  Intraday(this.points, this.regStart, this.regEnd, this.prevClose);
}

/// 除權息行事曆一列
class ExCalRow {
  final String date; // 民國日期字串
  final String code;
  final String name;
  final String kind; // 權/息
  final double cash;
  ExCalRow(this.date, this.code, this.name, this.kind, this.cash);
}

/// 選股排行一列
class Ranked {
  final String code;
  final String name;
  final double value; // 依榜別：漲跌% / 成交值(億) / 殖利率% / 本益比
  final double? price;
  Ranked(this.code, this.name, this.value, this.price);
}

double? _num(dynamic v) {
  final s = v?.toString().replaceAll(',', '').trim();
  if (s == null || s.isEmpty || s == '-') return null;
  return double.tryParse(s);
}

class MarketService {
  // 台股指數走 MIS（加權/櫃買，盤中即時）；其餘走 Yahoo（收盤 meta）
  static const _yahoo = <String, List<String>>{
    '美股': [
      '%5EIXIC|那斯達克',
      '%5EDJI|道瓊',
      '%5EGSPC|標普500',
      '%5ESOX|費城半導體',
    ],
    '亞洲': [
      '%5EN225|日經225',
      '000001.SS|上證指數',
      '%5EHSI|恆生指數',
      '%5EKS11|韓國KOSPI',
    ],
  };

  Future<List<IndexQuote>> indices() async {
    final out = <IndexQuote>[];

    // MIS 台股（盤中即時）：加權 tse_t00.tw、櫃買 otc_o00.tw
    try {
      final res = await misDio.get('/stock/api/getStockInfo.jsp',
          queryParameters: {
            'json': 1,
            'delay': 0,
            'ex_ch': 'tse_t00.tw|otc_o00.tw',
            '_': DateTime.now().millisecondsSinceEpoch,
          });
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      final arr = (data['msgArray'] as List?) ?? const [];
      for (final m in arr.cast<Map>()) {
        final isTaiex = (m['ch']?.toString() ?? '').startsWith('t00');
        final name = isTaiex ? '加權指數' : '櫃買指數';
        final v = _num(m['z']) ?? _num(m['pz']);
        if (v != null) {
          out.add(IndexQuote('台股', name, isTaiex ? '^TWII' : '^TWOII', v,
              _num(m['y'])));
        }
      }
    } catch (_) {}

    // MIS 盤後沒給指數值 → 用 Yahoo 補
    Future<void> yh(String sym, String name) async {
      if (out.any((e) => e.name == name)) return;
      try {
        final res = await yahooDio.get(
          'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(sym)}',
          queryParameters: {'range': '1d', 'interval': '1d'},
        );
        final mm = res.data['chart']?['result']?[0]?['meta'];
        if (mm == null) return;
        double? d(dynamic v) => (v is num) ? v.toDouble() : null;
        out.insert(
          0,
          IndexQuote('台股', name, sym, d(mm['regularMarketPrice']),
              d(mm['chartPreviousClose']) ?? d(mm['previousClose'])),
        );
      } catch (_) {}
    }

    await yh('^TWII', '加權指數');
    await yh('^TWOII', '櫃買指數');

    // Yahoo
    for (final entry in _yahoo.entries) {
      await Future.wait(entry.value.map((spec) async {
        final parts = spec.split('|');
        final ySym = Uri.decodeComponent(parts[0]);
        try {
          final res = await yahooDio.get(
            'https://query1.finance.yahoo.com/v8/finance/chart/${parts[0]}',
            queryParameters: {'range': '1d', 'interval': '1d'},
          );
          final mm = res.data['chart']?['result']?[0]?['meta'];
          if (mm == null) return;
          double? d(dynamic v) => (v is num) ? v.toDouble() : null;
          out.add(IndexQuote(
            entry.key,
            parts[1],
            ySym,
            d(mm['regularMarketPrice']),
            d(mm['chartPreviousClose']) ?? d(mm['previousClose']),
          ));
        } catch (_) {}
      }));
    }
    return out;
  }

  /// 任意指數/標的的歷史線（Yahoo），回傳收盤序列
  Future<List<Candle>> indexHistory(String ySymbol,
      {String range = '1y', String interval = '1d'}) async {
    try {
      final res = await yahooDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(ySymbol)}',
        queryParameters: {'range': range, 'interval': interval},
      );
      final r = res.data['chart']?['result']?[0];
      final ts = (r?['timestamp'] as List?)?.cast<int>() ?? const [];
      final q = r?['indicators']?['quote']?[0];
      final o = (q?['open'] as List?) ?? const [];
      final h = (q?['high'] as List?) ?? const [];
      final l = (q?['low'] as List?) ?? const [];
      final cl = (q?['close'] as List?) ?? const [];
      final out = <Candle>[];
      for (var i = 0; i < ts.length; i++) {
        final c = cl.length > i ? cl[i] : null;
        if (c == null) continue;
        double g(List x, double fb) =>
            x.length > i && x[i] != null ? (x[i] as num).toDouble() : fb;
        final cv = (c as num).toDouble();
        out.add(Candle(DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000),
            g(o, cv), g(h, cv), g(l, cv), cv, 0));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 美元/台幣匯率
  Future<IndexQuote?> fx() async {
    try {
      final res = await yahooDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/TWD=X',
        queryParameters: {'range': '1d', 'interval': '1d'},
      );
      final m = res.data['chart']?['result']?[0]?['meta'];
      if (m == null) return null;
      double? d(dynamic v) => (v is num) ? v.toDouble() : null;
      return IndexQuote('匯率', '美元/台幣', 'TWD=X', d(m['regularMarketPrice']),
          d(m['chartPreviousClose']) ?? d(m['previousClose']));
    } catch (_) {
      return null;
    }
  }

  /// 台股財經頭條（Google News RSS）
  Future<List<NewsHead>> headlines() async {
    try {
      final res = await webDio.get(
        'https://news.google.com/rss/search',
        queryParameters: {
          'q': '台股 OR 台積電 OR 加權指數',
          'hl': 'zh-TW',
          'gl': 'TW',
          'ceid': 'TW:zh-Hant',
        },
        options: Options(responseType: ResponseType.plain),
      );
      final xml = res.data as String;
      final items = RegExp(r'<item>(.*?)</item>', dotAll: true)
          .allMatches(xml)
          .take(12);
      String tag(String s, String t) =>
          RegExp('<$t>(.*?)</$t>', dotAll: true).firstMatch(s)?.group(1)?.trim() ??
          '';
      return items.map((m) {
        final b = m.group(1)!;
        var title = tag(b, 'title');
        title = title.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
        return NewsHead(title, tag(b, 'link'));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 分時（含盤前盤後）。regStart/regEnd 為正常交易時段的 epoch 秒。
  Future<Intraday> intraday(String ySymbol,
      {String range = '1d', String interval = '1m'}) async {
    var r = await _intradayOnce(ySymbol, range, interval, true);
    // 有些指數 1m 不回資料 → 退而求其次
    if (r.points.length < 2) {
      r = await _intradayOnce(ySymbol, range, '5m', false);
    }
    return r;
  }

  Future<Intraday> _intradayOnce(
      String ySymbol, String range, String interval, bool prePost) async {
    try {
      final res = await yahooDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(ySymbol)}',
        queryParameters: {
          'range': range,
          'interval': interval,
          'includePrePost': prePost,
        },
      );
      final r = res.data['chart']?['result']?[0];
      final ts = (r?['timestamp'] as List?)?.cast<int>() ?? const [];
      final q = r?['indicators']?['quote']?[0];
      final cl = (q?['close'] as List?) ?? const [];
      final vol = (q?['volume'] as List?) ?? const [];
      final pts = <Candle>[];
      for (var i = 0; i < ts.length; i++) {
        final c = i < cl.length ? cl[i] : null;
        if (c == null) continue;
        final v = (c as num).toDouble();
        pts.add(Candle(
          DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000),
          v,
          v,
          v,
          v,
          i < vol.length && vol[i] != null ? (vol[i] as num).toDouble() : 0,
        ));
      }
      final reg = r?['meta']?['currentTradingPeriod']?['regular'];
      return Intraday(
        pts,
        (reg?['start'] as num?)?.toInt(),
        (reg?['end'] as num?)?.toInt(),
        (r?['meta']?['chartPreviousClose'] as num?)?.toDouble(),
      );
    } catch (_) {
      return Intraday(const [], null, null, null);
    }
  }

  Future<List<Candle>> taiexIntraday() async {
    try {
      final res = await yahooDio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/%5ETWII',
        queryParameters: {'range': '1d', 'interval': '5m'},
      );
      final r = res.data['chart']?['result']?[0];
      final ts = (r?['timestamp'] as List?)?.cast<int>() ?? const [];
      final close = (r?['indicators']?['quote']?[0]?['close'] as List?) ??
          const [];
      final out = <Candle>[];
      for (var i = 0; i < ts.length; i++) {
        final c = close.length > i ? close[i] : null;
        if (c == null) continue;
        final v = (c as num).toDouble();
        out.add(Candle(
            DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000), v, v, v, v, 0));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<InstFlow>> institutions() async {
    final fmt = DateFormat('yyyyMMdd');
    for (var i = 0; i < 6; i++) {
      try {
        final d = DateTime.now().subtract(Duration(days: i));
        final res = await webDio.get('https://www.twse.com.tw/rwd/zh/fund/BFI82U',
            queryParameters: {
              'type': 'day',
              'response': 'json',
              'date': fmt.format(d),
            },
            options: Options(responseType: ResponseType.json));
        final j = res.data is Map ? res.data as Map : <String, dynamic>{};
        if (j['stat'] != 'OK') continue;
        final rows = (j['data'] as List).cast<List>();
        double net(String kw) {
          double sum = 0;
          for (final r in rows) {
            if ((r[0] as String).contains(kw)) {
              sum += double.tryParse((r[3] as String).replaceAll(',', '')) ?? 0;
            }
          }
          return sum / 1e8;
        }

        return [
          InstFlow('外資', net('外資')),
          InstFlow('投信', net('投信')),
          InstFlow('自營商', net('自營商')),
        ];
      } catch (_) {}
    }
    return const [];
  }

  Future<List<HotStock>> hot() async {
    try {
      final res = await webDio
          .get('https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX20');
      return (res.data as List).map((e) {
        final dir = e['Dir']?.toString() ?? '';
        final chg = _num(e['Change']) ?? 0;
        return HotStock(
          e['Code']?.toString() ?? '',
          e['Name']?.toString() ?? '',
          _num(e['ClosingPrice']),
          dir.contains('-') ? -chg : chg,
          (_num(e['TradeVolume']) ?? 0).toInt(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------- 選股排行（上市，收盤資料）--------------------
  List<dynamic>? _dayAll;
  List<dynamic>? _bwibbu;
  DateTime? _rankAt;

  Future<void> _ensureRank() async {
    if (_rankAt != null &&
        DateTime.now().difference(_rankAt!) < const Duration(minutes: 10)) {
      return;
    }
    try {
      final r = await webDio
          .get('https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL');
      _dayAll = r.data as List;
    } catch (_) {}
    try {
      final r = await webDio
          .get('https://openapi.twse.com.tw/v1/exchangeReport/BWIBBU_ALL');
      _bwibbu = r.data as List;
    } catch (_) {}
    _rankAt = DateTime.now();
  }

  /// 除權息行事曆（TWSE 除權除息預告表）
  Future<List<ExCalRow>> exCalendar() async {
    try {
      final r = await webDio.get(
        'https://www.twse.com.tw/rwd/zh/exRight/TWT48U',
        queryParameters: {'response': 'json'},
        options: Options(responseType: ResponseType.json),
      );
      final j = r.data is Map ? r.data as Map : {};
      if (j['stat'] != 'OK') return const [];
      final out = <ExCalRow>[];
      for (final e in (j['data'] as List).cast<List>()) {
        if (e.length < 8) continue;
        final code = e[1].toString().trim();
        if (code.isEmpty) continue;
        out.add(ExCalRow(e[0].toString(), code, e[2].toString().trim(),
            e[3].toString(), _num(e[7]) ?? 0));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Ranked>> ranking(String kind) async {
    await _ensureRank();
    if (kind == 'yield' || kind == 'pe') {
      final priceOf = <String, double>{
        for (final e in (_dayAll ?? []).cast<Map>())
          if (_num(e['ClosingPrice']) != null)
            e['Code'].toString(): _num(e['ClosingPrice'])!
      };
      final list = (_bwibbu ?? []).cast<Map>();
      final rows = <Ranked>[];
      for (final e in list) {
        final v = kind == 'yield'
            ? _num(e['DividendYield'])
            : _num(e['PEratio']);
        if (v == null || v <= 0) continue;
        final code = e['Code']?.toString() ?? '';
        rows.add(Ranked(code, e['Name']?.toString() ?? '', v, priceOf[code]));
      }
      rows.sort((a, b) =>
          kind == 'yield' ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
      return rows.take(40).toList();
    }

    final list = (_dayAll ?? []).cast<Map>();
    final rows = <Ranked>[];
    for (final e in list) {
      final close = _num(e['ClosingPrice']);
      final chg = _num(e['Change']);
      final val = _num(e['TradeValue']);
      if (close == null || close <= 0) continue;
      final prev = chg == null ? close : close - chg;
      final pct = prev == 0 ? 0.0 : (chg ?? 0) / prev * 100;
      final code = e['Code']?.toString() ?? '';
      final name = e['Name']?.toString() ?? '';
      if (code.length != 4) continue; // 濾掉 ETF/權證代號
      switch (kind) {
        case 'gain':
        case 'lose':
          rows.add(Ranked(code, name, pct, close));
          break;
        case 'value':
          rows.add(Ranked(code, name, (val ?? 0) / 1e8, close));
          break;
      }
    }
    if (kind == 'gain') {
      rows.sort((a, b) => b.value.compareTo(a.value));
    } else if (kind == 'lose') {
      rows.sort((a, b) => a.value.compareTo(b.value));
    } else {
      rows.sort((a, b) => b.value.compareTo(a.value));
    }
    return rows.take(40).toList();
  }

  /// 熱力圖用：成交值前 N 大個股的漲跌幅（同時要金額做格子大小、%做顏色）
  Future<List<HeatCell>> heatmap({int take = 60}) async {
    await _ensureRank();
    final list = (_dayAll ?? []).cast<Map>();
    final rows = <HeatCell>[];
    for (final e in list) {
      final close = _num(e['ClosingPrice']);
      final chg = _num(e['Change']);
      final val = _num(e['TradeValue']);
      final code = e['Code']?.toString() ?? '';
      final name = e['Name']?.toString() ?? '';
      if (close == null || close <= 0 || code.length != 4) continue;
      final prev = chg == null ? close : close - chg;
      final pct = prev == 0 ? 0.0 : (chg ?? 0) / prev * 100;
      rows.add(HeatCell(code, name, pct, (val ?? 0) / 1e8));
    }
    rows.sort((a, b) => b.turnoverYi.compareTo(a.turnoverYi));
    return rows.take(take).toList();
  }
}

class HeatCell {
  final String code;
  final String name;
  final double changePct;
  final double turnoverYi; // 成交值（億）
  HeatCell(this.code, this.name, this.changePct, this.turnoverYi);
}

final marketService = MarketService();
