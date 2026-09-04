import 'package:intl/intl.dart';

enum Market { tse, otc, us }

extension MarketX on Market {
  bool get isTW => this == Market.tse || this == Market.otc;
  String get misPrefix => this == Market.tse ? 'tse' : 'otc';
  String get yahooSuffix => switch (this) {
        Market.tse => '.TW',
        Market.otc => '.TWO',
        Market.us => '',
      };
  String get label => switch (this) {
        Market.tse => '上市',
        Market.otc => '上櫃',
        Market.us => '美股',
      };
}

Market marketFromName(String? s) => switch (s) {
      'otc' => Market.otc,
      'us' => Market.us,
      _ => Market.tse,
    };

/// 台股 ETF / ETN 代號都以 00 開頭（0050、0056、006208、00878、00679B…）
bool isEtfCode(String code) => code.startsWith('00') && code.length >= 4;

/// 自選股條目（代號 + 市場）
class Symbol {
  final String code;
  final Market market;
  const Symbol(this.code, this.market);

  String get id => '${market.name}:$code';
  factory Symbol.parse(String id) {
    final i = id.indexOf(':');
    final m = i < 0 ? 'tse' : id.substring(0, i);
    final code = i < 0 ? id : id.substring(i + 1);
    return Symbol(
        code,
        m == 'otc'
            ? Market.otc
            : m == 'us'
                ? Market.us
                : Market.tse);
  }
  @override
  bool operator ==(Object other) => other is Symbol && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// 即時報價（TWSE MIS）
class Quote {
  final String code;
  final String name;
  final double? price;
  final double? prevClose;
  final double? open;
  final double? high;
  final double? low;
  final double? limitUp;
  final double? limitDown;
  final int volume; // 總量（張）
  final List<PriceQty> bids; // 買五檔
  final List<PriceQty> asks; // 賣五檔
  final DateTime? time;

  Quote({
    required this.code,
    required this.name,
    this.price,
    this.prevClose,
    this.open,
    this.high,
    this.low,
    this.limitUp,
    this.limitDown,
    this.volume = 0,
    this.bids = const [],
    this.asks = const [],
    this.time,
  });

  double? get change =>
      (price != null && prevClose != null) ? price! - prevClose! : null;
  double? get changePct => (change != null && (prevClose ?? 0) != 0)
      ? change! / prevClose! * 100
      : null;
  bool get isLimitUp => price != null && limitUp != null && price! >= limitUp!;
  bool get isLimitDown =>
      price != null && limitDown != null && price! <= limitDown!;

  static double? _d(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty || s == '-') return null;
    return double.tryParse(s);
  }

  static List<PriceQty> _levels(String? prices, String? volumes) {
    if (prices == null || prices.isEmpty) return const [];
    final ps = prices.split('_').where((e) => e.isNotEmpty).toList();
    final vs = (volumes ?? '').split('_').where((e) => e.isNotEmpty).toList();
    final out = <PriceQty>[];
    for (var i = 0; i < ps.length; i++) {
      final p = double.tryParse(ps[i]);
      if (p == null || p == 0) continue;
      out.add(PriceQty(p, i < vs.length ? int.tryParse(vs[i]) ?? 0 : 0));
    }
    return out;
  }

  factory Quote.fromMis(Map<String, dynamic> m) {
    final last = _d(m['z']) ?? _d(m['pz']) ?? _d(m['o']) ?? _d(m['y']);
    return Quote(
      code: m['c']?.toString() ?? '',
      name: m['n']?.toString() ?? '',
      price: last,
      prevClose: _d(m['y']),
      open: _d(m['o']),
      high: _d(m['h']),
      low: _d(m['l']),
      limitUp: _d(m['u']),
      limitDown: _d(m['w']),
      volume: int.tryParse(m['v']?.toString() ?? '') ?? 0,
      bids: _levels(m['b']?.toString(), m['g']?.toString()),
      asks: _levels(m['a']?.toString(), m['f']?.toString()),
      time: int.tryParse(m['tlong']?.toString() ?? '') != null
          ? DateTime.fromMillisecondsSinceEpoch(int.parse(m['tlong'].toString()))
          : null,
    );
  }
}

class PriceQty {
  final double price;
  final int qty;
  const PriceQty(this.price, this.qty);
}

/// K 線一根
class Candle {
  final DateTime time;
  final double open, high, low, close;
  final double volume;
  Candle(this.time, this.open, this.high, this.low, this.close, this.volume);
}

/// 持倉
class Position {
  final String id;
  final String code;
  final Market market;
  final String name;
  final int shares; // 股（1 張 = 1000 股）
  final double cost; // 每股成本
  Position({
    required this.id,
    required this.code,
    required this.market,
    required this.name,
    required this.shares,
    required this.cost,
  });

  double get costValue => shares * cost;
  double marketValue(double? px) => px == null ? 0 : shares * px;
  double pnl(double? px) => px == null ? 0 : marketValue(px) - costValue;
  double pnlPct(double? px) => costValue == 0 ? 0 : pnl(px) / costValue * 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'market': market.name,
        'name': name,
        'shares': shares,
        'cost': cost,
      };
  factory Position.fromJson(Map<String, dynamic> j) => Position(
        id: j['id'],
        code: j['code'],
        market: marketFromName(j['market']),
        name: j['name'] ?? j['code'],
        shares: j['shares'],
        cost: (j['cost'] as num).toDouble(),
      );
}

/// 到價提醒
class PriceAlert {
  final String id;
  final String code;
  final Market market;
  final String name;
  final double target;
  final bool above; // true: 漲到 / false: 跌到
  bool triggered;
  final String kind; // 'price'（預設）或 'ma_cross'
  final int? maPeriod; // kind=ma_cross 時：均線天數（5/10/20/60）
  final bool? crossUp; // kind=ma_cross 時：true=站上、false=跌破
  PriceAlert({
    required this.id,
    required this.code,
    required this.market,
    required this.name,
    required this.target,
    required this.above,
    this.triggered = false,
    this.kind = 'price',
    this.maPeriod,
    this.crossUp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'market': market.name,
        'name': name,
        'target': target,
        'above': above,
        'triggered': triggered,
        'kind': kind,
        if (maPeriod != null) 'maPeriod': maPeriod,
        if (crossUp != null) 'crossUp': crossUp,
      };
  factory PriceAlert.fromJson(Map<String, dynamic> j) => PriceAlert(
        id: j['id'],
        code: j['code'],
        market: marketFromName(j['market']),
        name: j['name'] ?? j['code'],
        target: (j['target'] as num?)?.toDouble() ?? 0,
        above: j['above'] ?? true,
        triggered: j['triggered'] ?? false,
        kind: j['kind'] ?? 'price',
        maPeriod: j['maPeriod'] as int?,
        crossUp: j['crossUp'] as bool?,
      );
}

class NewsItem {
  final String title;
  final String url;
  final String source;
  final DateTime? published;
  NewsItem(this.title, this.url, this.source, this.published);
}

/// 可搜尋標的
class StockRef {
  final String code;
  final String name;
  final Market market;
  const StockRef(this.code, this.name, this.market);
  Symbol get symbol => Symbol(code, market);
}

/// 基本面 / 籌碼
class Fundamentals {
  final double? per; // 本益比
  final double? pbr; // 股價淨值比
  final double? yield_; // 殖利率 %
  final int? foreignNet; // 外資買賣超（股）
  final int? trustNet; // 投信
  final int? dealerNet; // 自營
  Fundamentals({
    this.per,
    this.pbr,
    this.yield_,
    this.foreignNet,
    this.trustNet,
    this.dealerNet,
  });
}

final nf0 = NumberFormat('#,##0');
final nf2 = NumberFormat('#,##0.00');
String signed(num v, [int dp = 2]) =>
    '${v > 0 ? '+' : ''}${v.toStringAsFixed(dp)}';
