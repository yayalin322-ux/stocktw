import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../state.dart';
import '../theme.dart';

/// 掃描別台手機分享的 QR 碼，把自選股/分組合併進來。
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
    _handled = true;
    try {
      final wl = ref.read(watchlistProvider.notifier);
      final (newGroups, newStocks) = wl.importMerge(raw);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newGroups + newStocks == 0
            ? '掃描成功，內容跟現有的都一樣'
            : '匯入完成：新增 $newGroups 個群組、$newStocks 檔股票'),
      ));
    } catch (_) {
      _handled = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('這不是自選股 QR 碼，或內容看不懂'),
        backgroundColor: AppColors.down,
      ));
    }
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
