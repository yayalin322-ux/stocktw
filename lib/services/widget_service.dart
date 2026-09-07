import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models.dart';
import 'market_service.dart';

/// 把自選股 / 大盤指數寫進 Android 桌面小工具。
/// 提供 4 種版面（同一份資料，不同 Provider 讀取）：
///   - StockWidgetProvider       自選股清單（最多 6 檔）
///   - StockSoloWidgetProvider   單一個股大字（自選第 1 檔）
///   - IndexWidgetProvider       大盤指數三欄（加權 / 櫃買 / 那斯達克）
///   - StockComboWidgetProvider  綜合（大盤一行 + 自選 3 檔）
/// 其他平台 / 還沒裝小工具時，home_widget 的呼叫會靜默失敗，不影響 App。
Future<void> updateHomeWidget(
    List<Symbol> watchlist, Map<String, Quote> quotes) async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
  try {
    // iOS 小工具透過 App Group 共享資料（要跟 Xcode 的 App Group 一致）
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId('group.com.willl.stocktw');
    }
    // 小工具空間小：股價保留 2 位、漲跌只顯示百分比（絕對數字最占空間、易被截斷）
    String pctText(double? pct) =>
        pct == null ? '' : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';

    // ---- 自選股（清單版 / 綜合版 / 單檔版共用；多寫幾檔給小工具設定畫面挑）----
    final items = <Map<String, dynamic>>[];
    for (final s in watchlist.take(20)) {
      final q = quotes[s.id];
      if (q == null || q.price == null) continue;
      final chg = q.change ?? 0;
      items.add({
        'code': s.code,
        'name': q.name.isNotEmpty ? q.name : s.code,
        'price': q.price!.toStringAsFixed(2),
        'change': chg,
        'changeText': pctText(q.changePct),
      });
    }
    await HomeWidget.saveWidgetData<String>('watchlist_json', jsonEncode(items));
    await HomeWidget.saveWidgetData<String>(
        'solo_json', jsonEncode(items.isNotEmpty ? items.first : {}));

    // ---- 分時走勢（給小工具畫線）：大盤 + 自選第 1 檔 ----
    try {
      final tx = await marketService.taiexIntraday();
      final sp = tx.map((c) => c.close).where((v) => v > 0).toList();
      if (sp.length > 2) {
        await HomeWidget.saveWidgetData<String>('spark_json', jsonEncode(sp));
      }
    } catch (_) {}
    try {
      if (watchlist.isNotEmpty) {
        final s0 = watchlist.first;
        final y = switch (s0.market) {
          Market.tse => '${s0.code}.TW',
          Market.otc => '${s0.code}.TWO',
          Market.us => s0.code,
        };
        final id = await marketService.intraday(y, range: '1d', interval: '5m');
        final sp = id.points.map((c) => c.close).where((v) => v > 0).toList();
        if (sp.length > 2) {
          await HomeWidget.saveWidgetData<String>(
              'spark_solo_json', jsonEncode(sp));
        }
      }
    } catch (_) {}

    // ---- 大盤指數（指數版 / 綜合版）----
    try {
      final idx = await marketService.indices();
      IndexQuote? pick(String name) {
        for (final q in idx) {
          if (q.name.contains(name)) return q;
        }
        return null;
      }

      final wanted = <IndexQuote?>[
        pick('加權') ?? (idx.isNotEmpty ? idx.first : null),
        pick('櫃買'),
        pick('那斯達克') ?? pick('NASDAQ'),
      ];
      final idxItems = <Map<String, dynamic>>[];
      for (final q in wanted) {
        if (q == null || q.value == null) continue;
        final chg = q.change ?? 0;
        // 指數數字大，小工具顯示整數 + 千分位
        final v = q.value!.round();
        final vStr = v.toString().replaceAllMapped(
            RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
        idxItems.add({
          'name': q.name,
          'value': vStr,
          'change': chg,
          'changeText': pctText(q.changePct),
        });
      }
      if (idxItems.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(
            'indices_json', jsonEncode(idxItems));
      }
    } catch (_) {
      // 指數抓不到就沿用上次寫入的
    }

    final now = DateTime.now();
    await HomeWidget.saveWidgetData<String>(
      'updatedAt',
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );

    if (Platform.isIOS) {
      await HomeWidget.updateWidget(iOSName: 'StockWidget');
      await HomeWidget.updateWidget(iOSName: 'IndexWidget');
    } else {
      for (final name in const [
        'StockWidgetProvider',
        'StockSoloWidgetProvider',
        'IndexWidgetProvider',
        'IndexSoloWidgetProvider',
        'StockComboWidgetProvider',
      ]) {
        await HomeWidget.updateWidget(name: name);
      }
    }
  } catch (_) {
    // 忽略：可能還沒加小工具、或平台不支援
  }
}
