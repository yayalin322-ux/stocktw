import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Firebase 是否初始化成功（尚未 flutterfire configure 時為 false，App 照常運作）
bool firebaseReady = false;

Future<void> initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e) {
    firebaseReady = false;
    debugPrint('Firebase 未啟用（$e）— 公告與背景推播停用');
  }
}
