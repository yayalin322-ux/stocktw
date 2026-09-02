import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase/fb.dart';
import 'firebase/push.dart';
import 'services/notifications.dart';
import 'state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await initNotifications();
  await initFirebase(); // 未 configure 時會靜默略過
  await initPush();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const StockApp(),
    ),
  );
}
