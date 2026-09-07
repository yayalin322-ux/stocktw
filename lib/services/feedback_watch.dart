import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/fb.dart';
import '../firebase/push.dart';
import '../pages/feedback_page.dart';
import 'notifications.dart';

/// App 開著時，即時監聽自己的意見反饋票券；一收到開發者回覆就「本機」發通知，
/// 不用等後台排程推播（那個 15 分鐘才跑一次）。
/// App 被系統完全終止時仍靠 FCM 推播（check-alerts 排程）補送。
class FeedbackWatch {
  static final _subs = <String, StreamSubscription<DocumentSnapshot>>{};
  static Timer? _rescan;

  static void start() {
    if (!firebaseReady) return;
    _attachAll();
    _rescan?.cancel();
    // 每 2 分鐘重掃一次，補上新開的票券、移除已結案的
    _rescan = Timer.periodic(const Duration(minutes: 2), (_) => _attachAll());
  }

  static void stop() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _rescan?.cancel();
  }

  // 這台裝置目前有效的 FCM token；很多舊票券建立當下還沒拿到 token，
  // 導致後台排程推播找不到對象。開 App 時補寫回去，下一輪排程就送得到。
  static String? _backfilledFor;
  static Future<void> _backfillToken(Iterable<String> ids) async {
    final tok = fcmToken;
    if (tok == null || tok == _backfilledFor) return;
    for (final id in ids) {
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .doc(id)
            .update({'deviceToken': tok, 'replyNoTokenTries': 0});
      } catch (_) {}
    }
    _backfilledFor = tok;
  }

  static Future<void> _attachAll() async {
    final tickets = await loadFeedbackTickets();
    final openIds = <String>{};
    for (final t in tickets) {
      if (t.id.isEmpty) continue;
      if (t.status != 'open' && t.status != 'pending_user_close') continue;
      openIds.add(t.id);
      if (_subs.containsKey(t.id)) continue;
      _subs[t.id] = FirebaseFirestore.instance
          .collection('feedback')
          .doc(t.id)
          .snapshots()
          .listen((snap) => _onSnap(t.id, snap),
              onError: (_) {});
    }
    // 移除已不再開啟的監聽
    for (final id in _subs.keys.toList()) {
      if (!openIds.contains(id)) {
        _subs.remove(id)?.cancel();
      }
    }
    if (openIds.isNotEmpty) await _backfillToken(openIds);
  }

  static Future<void> _onSnap(String id, DocumentSnapshot snap) async {
    final tickets = await loadFeedbackTickets();
    final idx = tickets.indexWhere((x) => x.id == id);
    if (idx < 0) return;
    final t = tickets[idx];

    if (!snap.exists) {
      t.status = 'closed';
      await saveFeedbackTickets(tickets);
      _subs.remove(id)?.cancel();
      return;
    }

    final v = snap.data() as Map<String, dynamic>;
    t.status = v['status'] as String? ?? t.status;
    t.needStock = v['needStock'] == true;
    t.needPhoto = v['needPhoto'] == true;
    if (v['stockCode'] != null) t.stockCode = v['stockCode'] as String?;
    if (v['stockName'] != null) t.stockName = v['stockName'] as String?;
    final remote = ((v['messages'] ?? []) as List)
        .map((e) => FbMsg.fromJson(e as Map))
        .toList();

    // 合併訊息
    final seen = {for (final m in t.messages) '${m.from}:${m.at}'};
    var changed = false;
    for (final m in remote) {
      if (!seen.contains('${m.from}:${m.at}')) {
        t.messages.add(m);
        changed = true;
      }
    }
    t.messages.sort((a, b) => a.at.compareTo(b.at));

    // 找出「比上次通知過的還新」的開發者訊息
    final newAdmin = t.messages
        .where((m) => m.from == 'admin' && m.at > t.seenAdminAt)
        .toList();
    if (newAdmin.isNotEmpty) {
      final last = newAdmin.last;
      t.seenAdminAt = last.at;
      changed = true;
      final body =
          last.text.length > 120 ? '${last.text.substring(0, 120)}…' : last.text;
      await notify('開發者回覆了「${t.subject}」', body);
    }

    if (changed) await saveFeedbackTickets(tickets);
  }
}
