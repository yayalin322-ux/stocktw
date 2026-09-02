import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'fb.dart';

class Announcement {
  final bool enabled;
  final String title;
  final String body;
  final String linkUrl;
  final String linkText;
  final int version;
  final bool blocking; // true = 維護中，強制擋畫面
  Announcement({
    required this.enabled,
    required this.title,
    required this.body,
    required this.linkUrl,
    required this.linkText,
    required this.version,
    required this.blocking,
  });

  factory Announcement.fromDoc(Map<String, dynamic> d) => Announcement(
        enabled: d['enabled'] == true,
        title: (d['title'] ?? '') as String,
        body: (d['body'] ?? '') as String,
        linkUrl: (d['linkUrl'] ?? '') as String,
        linkText: (d['linkText'] ?? '查看') as String,
        version: (d['version'] ?? 1) is int
            ? d['version'] as int
            : int.tryParse('${d['version']}') ?? 1,
        blocking: d['blocking'] == true,
      );
}

Future<Announcement?> fetchAnnouncement() async {
  if (!firebaseReady) return null;
  try {
    final snap = await FirebaseFirestore.instance
        .doc('config/announcement')
        .get(const GetOptions(source: Source.serverAndCache));
    final data = snap.data();
    if (data == null) return null;
    return Announcement.fromDoc(data);
  } catch (_) {
    return null;
  }
}

/// 在 App 啟動時呼叫；有公告且未看過就跳出。
Future<void> maybeShowAnnouncement(BuildContext context) async {
  final a = await fetchAnnouncement();
  if (a == null || !a.enabled || a.title.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getInt('announce.seenVersion') ?? 0;
  if (!a.blocking && a.version <= seen) return;
  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: !a.blocking,
    builder: (_) => PopScope(
      canPop: !a.blocking,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(a.title),
        content: SingleChildScrollView(child: Text(a.body)),
        actions: [
          if (a.linkUrl.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(a.linkUrl),
                  mode: LaunchMode.externalApplication),
              child: Text(a.linkText),
            ),
          if (!a.blocking)
            FilledButton(
              onPressed: () {
                prefs.setInt('announce.seenVersion', a.version);
                Navigator.pop(context);
              },
              child: const Text('知道了'),
            ),
        ],
      ),
    ),
  );
}
