// ignore_for_file: avoid_print
// 資料層煙霧測試：dart run bin/smoke.dart
import '../lib/models.dart';
import '../lib/services/candle_service.dart';
import '../lib/services/financials_service.dart';
import '../lib/services/market_service.dart';
import '../lib/services/quote_service.dart';
import '../lib/services/yahoo_service.dart';

Future<void> main() async {
  print('── 台股 + 美股報價（統一入口）──');
  final qs = await quoteService.fetch(const [
    Symbol('2330', Market.tse),
    Symbol('AAPL', Market.us),
    Symbol('NVDA', Market.us),
  ]);
  qs.forEach((k, q) => print('  $k  ${q.name}  ${q.price}  '
      '${q.change?.toStringAsFixed(2)} (${q.changePct?.toStringAsFixed(2)}%)'));

  print('\n── 美股搜尋（Yahoo）──');
  for (final r in await yahooService.search('nvidia')) {
    print('  ${r.code}  ${r.name}');
  }

  print('\n── 首頁多國指數 ──');
  for (final i in await marketService.indices()) {
    print('  [${i.group}] ${i.name}  ${i.value}  '
        '${i.change?.toStringAsFixed(2)} (${i.changePct?.toStringAsFixed(2)}%)');
  }

  print('\n── 選股排行 ──');
  for (final kind in ['gain', 'lose', 'value', 'yield', 'pe']) {
    final r = await marketService.ranking(kind);
    final top = r.take(3).map((x) => '${x.name}(${x.value.toStringAsFixed(2)})').join('、');
    print('  $kind：$top');
  }

  print('\n── 美股 K 線 (AAPL) ──');
  final k = await candleService.fetch(const Symbol('AAPL', Market.us),
      range: '1mo');
  print('  ${k.length} 根，最後收 ${k.isEmpty ? "-" : k.last.close}');

  print('\n── 台股財報 (2330) 仍正常 ──');
  final inc = await financialsService.income('2330');
  print('  ${inc?.period}  EPS ${inc?.eps}  毛利率 ${inc?.grossMargin?.toStringAsFixed(1)}%');

  print('\n✅ done');
}
