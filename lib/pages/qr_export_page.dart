import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state.dart';
import '../theme.dart';

/// 把自選股＋分組編成 QR 碼，給別台手機掃描匯入。
class QrExportPage extends ConsumerWidget {
  const QrExportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchlistProvider); // 資料變動時重新產生
    final wl = ref.read(watchlistProvider.notifier);
    final payload = wl.exportPayload();
    final tooBig = payload.length > 1800;

    return Scaffold(
      appBar: AppBar(title: const Text('分享自選股')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tooBig)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '資料有點多（${wl.groupNames.length} 個群組），QR 碼可能不好掃，'
                    '建議刪減一些群組或分開幾次匯出。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.warn),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text('${wl.groupNames.length} 個群組・共 '
                  '${wl.groupNames.fold(0, (a, g) => a + wl.countOf(g))} 檔股票'),
              const SizedBox(height: 6),
              const Text('請對方在自選股頁點「掃描 QR 匯入」對準這個畫面',
                  style: TextStyle(fontSize: 12, color: AppColors.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}
