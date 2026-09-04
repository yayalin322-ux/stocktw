import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firebase/fb.dart';
import '../firebase/push.dart';
import '../theme.dart';

/// 意見反饋／客服：直接寫進後台的 Firestore，不需要你的 email。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _msgC = TextEditingController();
  final _contactC = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  Future<void> _send() async {
    final msg = _msgC.text.trim();
    if (msg.isEmpty) return;
    if (!firebaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法送出，請確認網路連線後再試')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('feedback').add({
        'message': msg,
        'contact': _contactC.text.trim(),
        'deviceToken': fcmToken,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送出失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('意見反饋')),
      body: _sent
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.up, size: 48),
                    const SizedBox(height: 12),
                    const Text('已送出，謝謝你的回饋！',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _sent = false;
                        _msgC.clear();
                      }),
                      child: const Text('再寫一則'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('回報問題、建議新功能，或單純想抱怨報價不準都可以，'
                    '內容會直接送到開發者的後台。',
                    style: TextStyle(fontSize: 13, color: AppColors.ink2)),
                const SizedBox(height: 16),
                TextField(
                  controller: _msgC,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: '想說的話',
                    hintText: '例如：熱力圖的漲跌幅怪怪的、希望加上……',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contactC,
                  decoration: const InputDecoration(
                    labelText: '聯絡方式（選填）',
                    hintText: '想要回覆的話留 email 或其他聯絡方式',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('送出'),
                ),
              ],
            ),
    );
  }
}
