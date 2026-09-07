import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase/fb.dart';
import 'firebase/push.dart';
import 'pages/feedback_page.dart';
import 'services/feedback_watch.dart';
import 'services/notifications.dart';
import 'state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await initNotifications();
  await initFirebase(); // 未 configure 時會靜默略過
  await initPush();
  FeedbackWatch.start(); // App 開著時即時監聽意見反饋回覆，收到就本機發通知
  refreshFeedbackUnread(); // 主頁齒輪紅點：未讀的開發者回覆數
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const StockApp(),
    ),
  );
}
