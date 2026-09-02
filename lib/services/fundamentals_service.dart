import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'api.dart';

/// 基本面 + 三大法人（免金鑰；法人為最近一個交易日）
class FundamentalsService {
  List<dynamic>? _bwibbu; // 本益比/殖利率/淨值比（TWSE OpenAPI）
  Map<String, List<String>> _t86 = {}; // code -> data row（TWSE 日報）
  DateTime? _loadedAt;

  Future<void> _ensure() async {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(hours: 3)) {
      return;
    }
    // 基本面
    try {
      final r = await webDio.get(
        'https://openapi.twse.com.tw/v1/exchangeReport/BWIBBU_ALL',
        options: Options(responseType: ResponseType.json),
      );
      _bwibbu = r.data as List;
    } catch (_) {}

    // 三大法人：往回找最近有資料的交易日
    final fmt = DateFormat('yyyyMMdd');
    for (var i = 0; i < 6; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      try {
        final r = await webDio.get(
          'https://www.twse.com.tw/rwd/zh/fund/T86',
          queryParameters: {
            'date': fmt.format(d),
            'selectType': 'ALL',
            'response': 'json',
          },
          options: Options(responseType: ResponseType.json),
        );
        final j = r.data is String
            ? (r.data as String)
            : r.data as Map<String, dynamic>;
        final map = j is Map ? j : <String, dynamic>{};
        if (map['stat'] == 'OK' && map['data'] is List) {
          _t86 = {
            for (final row in (map['data'] as List))
              (row[0] as String).trim(): (row as List).cast<String>()
          };
          break;
        }
      } catch (_) {}
    }
    _loadedAt = DateTime.now();
  }

  Future<Fundamentals> fetch(String code) async {
    await _ensure();
    double? d(dynamic v) =>
        double.tryParse(v?.toString().replaceAll(',', '') ?? '');
    int? i(String? v) => int.tryParse(v?.replaceAll(',', '').trim() ?? '');

    final b = _bwibbu?.cast<Map>().firstWhere(
          (e) => e['Code'] == code,
          orElse: () => {},
        );
    final row = _t86[code];

    return Fundamentals(
      per: b == null || b.isEmpty ? null : d(b['PEratio']),
      pbr: b == null || b.isEmpty ? null : d(b['PBratio']),
      yield_: b == null || b.isEmpty ? null : d(b['DividendYield']),
      foreignNet: row == null ? null : i(row[4]), // 外陸資買賣超(不含外資自營商)
      trustNet: row == null ? null : i(row[10]), // 投信買賣超
      dealerNet: row == null ? null : i(row[11]), // 自營商買賣超
    );
  }
}

final fundamentalsService = FundamentalsService();
