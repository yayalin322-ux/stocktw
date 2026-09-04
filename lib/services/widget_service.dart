import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models.dart';

/// 把自選股前 5 檔寫進 Android 桌面小工具（StockWidgetProvider）。
/// 目前只做 Android；其他平台 / 還沒裝小工具時，home_widget 的呼叫會
/// 静默失敗或無事發生，不影響 App 本身。
Future<void> updateHomeWidget(
    List<Symbol> watchlist, Map<String, Quote> quotes) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final items = <Map<String, dynamic>>[];
    for (final s in watchlist.take(5)) {
      final q = quotes[s.id];
      if (q == null || q.price == null) continue;
      final chg = q.change ?? 0;
      final pct = q.changePct;
      final arrow = chg > 0 ? '▲' : (chg < 0 ? '▼' : '');
      items.add({
        'name': q.name.isNotEmpty ? q.name : s.code,
        'price': q.price!.toStringAsFixed(2),
        'change': chg,
        'changeText':
            '$arrow${chg.abs().toStringAsFixed(2)} ${pct != null ? '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%' : ''}',
      });
    }
    await HomeWidget.saveWidgetData<String>('watchlist_json', jsonEncode(items));
    final now = DateTime.now();
    await HomeWidget.saveWidgetData<String>(
      'updatedAt',
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
    await HomeWidget.updateWidget(name: 'StockWidgetProvider');
  } catch (_) {
    // 忽略：可能還沒加小工具、或平台不支援
  }
}
