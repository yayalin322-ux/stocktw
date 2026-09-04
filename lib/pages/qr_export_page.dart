import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state.dart';
import '../theme.dart';

/// 把自選股／持倉編成 QR 碼，給別台手機掃描匯入。可以選要匯出哪些資料。
class QrExportPage extends ConsumerStatefulWidget {
  const QrExportPage({super.key});
  @override
  ConsumerState<QrExportPage> createState() => _QrExportPageState();
}

class _QrExportPageState extends ConsumerState<QrExportPage> {
  bool _wl = true;
  bool _pf = true;

  @override
  Widget build(BuildContext context) {
    ref.watch(watchlistProvider);
    ref.watch(portfolioProvider);
    final wl = ref.read(watchlistProvider.notifier);
    final pf = ref.read(portfolioProvider.notifier);

    final payload = jsonEncode({
      't': 'stocktw',
      'v': 2,
      if (_wl) 'wl': wl.exportMap(),
      if (_pf) 'pf': pf.exportMap(),
    });
    final hasContent = _wl || _pf;
    final tooBig = payload.length > 1800;

    return Scaffold(
      appBar: AppBar(title: const Text('分享資料')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: _wl,
                      onChanged: (v) => setState(() => _wl = v ?? false),
                      title: const Text('自選股與分組'),
                      subtitle: Text(
                          '${wl.groupNames.length} 個群組・共 ${wl.totalCount} 檔'),
                    ),
                    CheckboxListTile(
                      value: _pf,
                      onChanged: (v) => setState(() => _pf = v ?? false),
                      title: const Text('持倉'),
                      subtitle: Text('共 ${pf.exportMap().length} 檔'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (tooBig)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    '資料有點多，QR 碼可能不好掃，建議只選一項匯出，或刪減群組/持倉。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.warn),
                  ),
                ),
              if (!hasContent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('請至少勾選一項要分享的資料',
                      style: TextStyle(color: AppColors.ink3)),
                )
              else
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
              const SizedBox(height: 16),
              const Text('請對方在自選股頁點「掃描 QR 匯入」對準這個畫面',
                  style: TextStyle(fontSize: 12, color: AppColors.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}
