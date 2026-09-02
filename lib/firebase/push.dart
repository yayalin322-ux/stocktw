import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../services/notifications.dart';
import 'fb.dart';

String? fcmToken;

bool get _mobile =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // 背景收到推播由系統托盤顯示，這裡不需額外處理
}

Future<void> initPush() async {
  if (!firebaseReady || !_mobile) return;
  try {
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    fcmToken = await fm.getToken();
    if (fcmToken != null) await _writeDevice(fcmToken!);
    fm.onTokenRefresh.listen((t) {
      fcmToken = t;
      _writeDevice(t);
    });

    // 前景收到 → 用本地通知顯示
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n != null) notify(n.title ?? '到價提醒', n.body ?? '');
    });
  } catch (e) {
    debugPrint('initPush 失敗：$e');
  }
}

Future<void> _writeDevice(String token) async {
  try {
    await FirebaseFirestore.instance.doc('devices/$token').set({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (_) {}
}

/// 每次提醒清單變動時呼叫：把提醒同步到雲端，供排程 function 比價推播
Future<void> syncAlerts(List<PriceAlert> alerts) async {
  if (!firebaseReady || !_mobile || fcmToken == null) return;
  try {
    await FirebaseFirestore.instance.doc('deviceAlerts/$fcmToken').set({
      'token': fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
      'alerts': [
        for (final a in alerts)
          {
            'id': a.id,
            'code': a.code,
            'market': a.market.name,
            'name': a.name,
            'target': a.target,
            'above': a.above,
            'triggered': a.triggered,
          }
      ],
    });
  } catch (_) {}
}
