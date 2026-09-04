import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';

/// 掃描別台手機分享的 QR 碼，選擇要匯入哪些資料再合併進來。
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});
  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;

    Map<String, dynamic>? wlMap;
    List<dynamic>? pfList;
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) throw const FormatException('格式不對');
      if (obj['t'] == 'stocktw') {
        if (obj['wl'] is Map) wlMap = Map<String, dynamic>.from(obj['wl']);
        if (obj['pf'] is List) pfList = obj['pf'] as List;
      } else if (obj['t'] == 'wl') {
        wlMap = Map<String, dynamic>.from(obj); // 舊版相容
      } else {
        throw const FormatException('不是本 App 的資料 QR 碼');
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('這不是本 App 的資料 QR 碼，或內容看不懂'),
        backgroundColor: AppColors.down,
      ));
      return;
    }
    if (wlMap == null && pfList == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('這個 QR 碼沒有可匯入的資料'),
        backgroundColor: AppColors.down,
      ));
      return;
    }
    _handled = true;
    _confirm(wlMap, pfList);
  }

  Future<void> _confirm(
      Map<String, dynamic>? wlMap, List<dynamic>? pfList) async {
    var pickWl = wlMap != null;
    var pickPf = pfList != null;
    final wlGroups = wlMap == null ? 0 : (wlMap['g'] as List? ?? const []).length;
    final wlStocks = wlMap == null
        ? 0
        : (wlMap['g'] as List? ?? const [])
            .fold<int>(0, (a, g) => a + ((g['s'] as List? ?? const []).length));

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('選擇要匯入的資料'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wlMap != null)
                CheckboxListTile(
                  value: pickWl,
                  onChanged: (v) => setSt(() => pickWl = v ?? false),
                  title: const Text('自選股與分組'),
                  subtitle: Text('$wlGroups 個群組・共 $wlStocks 檔'),
                ),
              if (pfList != null)
                CheckboxListTile(
                  value: pickPf,
                  onChanged: (v) => setSt(() => pickPf = v ?? false),
                  title: const Text('持倉'),
                  subtitle: Text('共 ${pfList.length} 檔（只會新增，不會覆蓋你已記錄的成本）'),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('匯入')),
          ],
        ),
      ),
    );

    if (go != true || (!pickWl && !pickPf)) {
      _handled = false;
      return;
    }

    var msg = <String>[];
    if (pickWl && wlMap != null) {
      final (newGroups, newStocks) =
          ref.read(watchlistProvider.notifier).importMerge(wlMap);
      msg.add('自選股：新增 $newGroups 個群組、$newStocks 檔');
    }
    if (pickPf && pfList != null) {
      final positions = pfList
          .whereType<Map>()
          .map((e) => Position.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final added =
          ref.read(portfolioProvider.notifier).importMerge(positions);
      msg.add('持倉：新增 $added 檔');
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? '沒有新增任何資料' : msg.join('　'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掃描 QR 匯入')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: const Text('把對方畫面上的 QR 碼對準框內',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
