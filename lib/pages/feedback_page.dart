import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../feedback_meta.dart';
import '../firebase/fb.dart';
import '../firebase/push.dart';
import '../theme.dart';
import 'search_page.dart';

// ---------------------------------------------------------------------------
// 本地票券模型
// ---------------------------------------------------------------------------
class FbMsg {
  final String from; // 'user' | 'admin'
  final String text;
  final int at;
  final List<String> images; // base64 jpeg（縮圖後）
  FbMsg(this.from, this.text, this.at, {this.images = const []});
  Map<String, dynamic> toJson() => {
        'from': from,
        'text': text,
        'at': at,
        if (images.isNotEmpty) 'images': images,
      };
  factory FbMsg.fromJson(Map j) => FbMsg(
        j['from'] ?? 'user',
        j['text'] ?? '',
        (j['at'] ?? 0) as int,
        images: ((j['images'] ?? const []) as List)
            .map((e) => '$e')
            .toList(),
      );
}

/// 選最多 2 張照片、縮圖、轉 base64，總量控制在 ~700KB 內（Firestore 單筆 1MB）。
Future<List<String>> pickFeedbackImages() async {
  try {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
        maxWidth: 1000, maxHeight: 1000, imageQuality: 45);
    final out = <String>[];
    var total = 0;
    for (final x in picked.take(2)) {
      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);
      if (total + b64.length > 700000) continue;
      total += b64.length;
      out.add(b64);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

class FbTicket {
  final String id;
  final String category;
  final String subject;
  String status; // open | pending_user_close（開發者請使用者確認結案）| closed
  final int priority;
  final int createdAt;
  List<FbMsg> messages;
  int seenAdminAt; // 使用者「真的點進去看過」的最後一則 admin 訊息時間
  int notifiedAdminAt; // 已在本機發過通知的最後一則 admin 訊息時間
  String? stockCode; // 報價/資料錯誤類：相關個股
  String? stockName;
  int rating; // 結案後使用者滿意度 0=未評 1=不滿意 2=普通 3=滿意
  bool needStock; // 開發者要求使用者補上是哪一檔股票
  bool needPhoto; // 開發者要求使用者補上截圖
  FbTicket(this.id, this.category, this.subject, this.status, this.priority,
      this.createdAt, this.messages,
      {this.seenAdminAt = 0,
      this.notifiedAdminAt = 0,
      this.stockCode,
      this.stockName,
      this.rating = 0,
      this.needStock = false,
      this.needPhoto = false});

  /// 有沒有「使用者還沒看過」的開發者回覆
  bool get hasUnreadAdmin =>
      messages.any((m) => m.from == 'admin' && m.at > seenAdminAt);

  int get lastAdminAt {
    var t = 0;
    for (final m in messages) {
      if (m.from == 'admin' && m.at > t) t = m.at;
    }
    return t;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'subject': subject,
        'status': status,
        'priority': priority,
        'createdAt': createdAt,
        'messages': messages.map((m) => m.toJson()).toList(),
        'seenAdminAt': seenAdminAt,
        'notifiedAdminAt': notifiedAdminAt,
        if (stockCode != null) 'stockCode': stockCode,
        if (stockName != null) 'stockName': stockName,
        'rating': rating,
        'needStock': needStock,
        'needPhoto': needPhoto,
      };
  factory FbTicket.fromJson(Map j) => FbTicket(
        j['id'] ?? '',
        j['category'] ?? 'other',
        j['subject'] ?? '',
        j['status'] ?? 'open',
        (j['priority'] ?? 0) as int,
        (j['createdAt'] ?? 0) as int,
        ((j['messages'] ?? []) as List)
            .map((e) => FbMsg.fromJson(e as Map))
            .toList(),
        seenAdminAt: (j['seenAdminAt'] ?? 0) as int,
        notifiedAdminAt:
            (j['notifiedAdminAt'] ?? j['seenAdminAt'] ?? 0) as int,
        stockCode: j['stockCode'] as String?,
        stockName: j['stockName'] as String?,
        rating: (j['rating'] ?? 0) as int,
        needStock: j['needStock'] == true,
        needPhoto: j['needPhoto'] == true,
      );
}

const _prefsKey = 'feedback_tickets';

Future<List<FbTicket>> loadFeedbackTickets() async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(_prefsKey);
  if (raw == null) return [];
  try {
    return (jsonDecode(raw) as List)
        .map((e) => FbTicket.fromJson(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveFeedbackTickets(List<FbTicket> ts) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString(_prefsKey, jsonEncode(ts.map((t) => t.toJson()).toList()));
}

/// 未讀的開發者回覆數（給主頁齒輪、意見反饋入口顯示紅點用）。
/// App 各處以 ValueListenableBuilder 監聽，收到回覆或使用者看過都會刷新。
final ValueNotifier<int> feedbackUnread = ValueNotifier<int>(0);

Future<void> refreshFeedbackUnread() async {
  try {
    final ts = await loadFeedbackTickets();
    feedbackUnread.value = ts.where((t) => t.hasUnreadAdmin).length;
  } catch (_) {}
}

bool _fbReplyPrompted = false;

/// App 啟動後叫一次：若有沒看過的開發者回覆，跳一個明顯的對話框提醒。
Future<void> maybeShowFeedbackReplies(BuildContext context) async {
  if (_fbReplyPrompted) return;
  _fbReplyPrompted = true;
  final ts = await loadFeedbackTickets();
  final unread = ts.where((t) => t.hasUnreadAdmin).toList();
  feedbackUnread.value = unread.length;
  if (unread.isEmpty || !context.mounted) return;
  final one = unread.first;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.mark_chat_unread_outlined, color: AppColors.accent),
      title: Text(unread.length == 1
          ? '開發者回覆了你的意見反饋'
          : '開發者回覆了 ${unread.length} 則意見反饋'),
      content: Text(
        unread.length == 1
            ? '「${one.subject}」有新回覆，點開看看。'
            : '有 ${unread.length} 則反饋收到新回覆，點開看看。',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('稍後')),
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackPage()),
            );
          },
          child: const Text('查看'),
        ),
      ],
    ),
  );
}

String _fmt(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 把常見錯誤翻成白話提示
String friendlyError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('network') ||
      s.contains('unavailable') ||
      s.contains('timeout') ||
      s.contains('socket') ||
      s.contains('connection')) {
    return '網路好像不太穩，確認連線後再試一次';
  }
  if (s.contains('resource-exhausted') ||
      s.contains('quota') ||
      s.contains('too many') ||
      s.contains('rate')) {
    return '剛剛動作太快了，稍等幾秒再送一次';
  }
  if (s.contains('permission-denied') || s.contains('unauthenticated')) {
    return '這個動作目前無法完成，請稍後再試';
  }
  if (s.contains('invalid') && s.contains('argument')) {
    return '內容格式有問題，檢查一下（例如圖片太大）再送';
  }
  return '送出失敗，請稍後再試';
}

// ---------------------------------------------------------------------------
// 票券列表
// ---------------------------------------------------------------------------
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  bool _loading = true;
  List<FbTicket> _tickets = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final local = await loadFeedbackTickets();
    if (firebaseReady) {
      for (final t in local) {
        try {
          final d = await FirebaseFirestore.instance
              .collection('feedback')
              .doc(t.id)
              .get();
          if (!d.exists) {
            // 後台結案 10 天後已刪除，本地保留、標記結案
            t.status = 'closed';
            continue;
          }
          final v = d.data()!;
          t.status = v['status'] as String? ?? t.status;
          t.needStock = v['needStock'] == true;
          t.needPhoto = v['needPhoto'] == true;
          if (v['stockCode'] != null) t.stockCode = v['stockCode'] as String?;
          if (v['stockName'] != null) t.stockName = v['stockName'] as String?;
          if ((v['rating'] ?? 0) is int && (v['rating'] ?? 0) as int > 0) {
            t.rating = v['rating'] as int;
          }
          final remote = ((v['messages'] ?? []) as List)
              .map((e) => FbMsg.fromJson(e as Map))
              .toList();
          // 合併：以 (from+at) 當 key，補進本地沒有的（主要是 admin 回覆）
          final seen = {for (final m in t.messages) '${m.from}:${m.at}'};
          for (final m in remote) {
            if (!seen.contains('${m.from}:${m.at}')) t.messages.add(m);
          }
          t.messages.sort((a, b) => a.at.compareTo(b.at));
          // 收到回覆但使用者還沒點進去看 → 不動 seenAdminAt，讓列表維持「新回覆」標記；
          // 只把 notifiedAdminAt 補上，避免監聽器重覆發通知。
          if (t.lastAdminAt > t.notifiedAdminAt) {
            t.notifiedAdminAt = t.lastAdminAt;
          }
        } catch (_) {}
      }
      await saveFeedbackTickets(local);
    }
    await refreshFeedbackUnread();
    if (mounted) {
      setState(() {
        int rank(FbTicket t) {
          if (t.hasUnreadAdmin) return 0; // 有新回覆的排最前面
          if (t.status == 'pending_user_close') return 1;
          if (t.status == 'closed') return 3;
          return 2;
        }

        _tickets = local
          ..sort((a, b) {
            final r = rank(a).compareTo(rank(b));
            if (r != 0) return r;
            return b.createdAt.compareTo(a.createdAt);
          });
        _loading = false;
      });
    }
  }

  Future<void> _newTicket() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewTicketPage()),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('意見反饋'),
        actions: [
          IconButton(
            tooltip: '新增反饋',
            icon: const Icon(Icons.add),
            onPressed: _newTicket,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _tickets.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.forum_outlined,
                                  size: 40, color: AppColors.ink3),
                              const SizedBox(height: 10),
                              Text('還沒有反饋，右上角 + 新增',
                                  style: TextStyle(color: AppColors.ink3)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _tickets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = _tickets[i];
                        final last = t.messages.isNotEmpty
                            ? t.messages.last
                            : null;
                        final hasReply =
                            t.messages.any((m) => m.from == 'admin');
                        final unread = t.hasUnreadAdmin;
                        return Dismissible(
                          key: ValueKey(t.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: AppColors.down,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete,
                                color: Colors.white),
                          ),
                          confirmDismiss: (_) async => await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  content: const Text('從這支手機移除這則反饋？'
                                      '（不影響開發者後台的紀錄）'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('取消')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, true),
                                        child: const Text('移除')),
                                  ],
                                ),
                              ) ??
                              false,
                          onDismissed: (_) async {
                            final ts = await loadFeedbackTickets();
                            ts.removeWhere((x) => x.id == t.id);
                            await saveFeedbackTickets(ts);
                            setState(() => _tickets.removeWhere(
                                (x) => x.id == t.id));
                          },
                          child: ListTile(
                          tileColor: unread
                              ? AppColors.accent.withValues(alpha: 0.10)
                              : null,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TicketDetailPage(ticket: t)),
                            );
                            _refresh();
                          },
                          leading: _priorityDot(t.priority, t.status),
                          title: Row(
                            children: [
                              if (unread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: const BoxDecoration(
                                      color: AppColors.down,
                                      shape: BoxShape.circle),
                                ),
                              Expanded(
                                child: Text(t.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${categoryOf(t.category).label}'
                            '${last != null ? '　${last.from == 'admin' ? '開發者：' : ''}${last.text}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.ink3),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (unread)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.down,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('新回覆',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                )
                              else if (t.status == 'pending_user_close')
                                Text('待你確認',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.warn))
                              else if (t.status == 'closed')
                                Text('已結案',
                                    style: TextStyle(
                                        fontSize: 11, color: AppColors.ink3))
                              else if (hasReply)
                                Text('已回覆',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accent))
                              else
                                Text('處理中',
                                    style: TextStyle(
                                        fontSize: 11, color: AppColors.warn)),
                              const SizedBox(height: 2),
                              Text(_fmt(t.createdAt),
                                  style: TextStyle(
                                      fontSize: 10, color: AppColors.ink3)),
                            ],
                          ),
                        ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _priorityDot(int p, String status) {
    final c = status == 'closed'
        ? AppColors.ink3
        : status == 'pending_user_close'
        ? AppColors.warn
        : (p >= 2
            ? AppColors.up
            : p == 1
                ? AppColors.warn
                : AppColors.flat);
    return Container(width: 10, height: 10,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }
}

// ---------------------------------------------------------------------------
// 新增反饋：先選分類 → 看常見問題 → 填主題與內容
// ---------------------------------------------------------------------------
class NewTicketPage extends StatefulWidget {
  final String? presetStockCode;
  final String? presetStockName;
  const NewTicketPage(
      {super.key, this.presetStockCode, this.presetStockName});
  @override
  State<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<NewTicketPage> {
  FeedbackCategory? _cat;
  final _subjectC = TextEditingController();
  final _bodyC = TextEditingController();
  final _contactC = TextEditingController();
  bool _sending = false;
  String? _stockCode;
  String? _stockName;
  String? _subtype;
  List<String> _images = [];

  @override
  void initState() {
    super.initState();
    if (widget.presetStockCode != null) {
      _stockCode = widget.presetStockCode;
      _stockName = widget.presetStockName;
      _cat = kFeedbackCategories.firstWhere((c) => c.key == 'data',
          orElse: () => kFeedbackCategories.last);
    }
  }

  Future<void> _submit() async {
    final cat = _cat!;
    var subject = _subjectC.text.trim();
    if (_subtype != null && !subject.startsWith('[')) {
      subject = '[$_subtype] $subject';
    }
    final body = _bodyC.text.trim();
    if (_subjectC.text.trim().isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填主題和內容')),
      );
      return;
    }
    if (!firebaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法送出，請確認網路後再試')),
      );
      return;
    }
    setState(() => _sending = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final priority = autoPriority(cat.key, subject, body);
    final firstMsg = _contactC.text.trim().isEmpty
        ? body
        : '$body\n\n（聯絡方式：${_contactC.text.trim()}）';
    try {
      final ref = await FirebaseFirestore.instance.collection('feedback').add({
        'category': cat.key,
        'subject': subject,
        'status': 'open',
        'priority': priority,
        'deviceToken': fcmToken,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (_stockCode != null) 'stockCode': _stockCode,
        if (_stockName != null) 'stockName': _stockName,
        'messages': [
          {
            'from': 'user',
            'text': firstMsg,
            'at': now,
            if (_images.isNotEmpty) 'images': _images,
          },
        ],
      });
      final ts = await loadFeedbackTickets();
      ts.add(FbTicket(ref.id, cat.key, subject, 'open', priority, now,
          [FbMsg('user', firstMsg, now, images: _images)],
          stockCode: _stockCode, stockName: _stockName));
      await saveFeedbackTickets(ts);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return Scaffold(
      appBar: AppBar(title: Text(cat == null ? '選擇主題分類' : cat.label)),
      body: cat == null
          ? ListView(
              children: [
                for (final c in kFeedbackCategories)
                  ListTile(
                    title: Text(c.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _cat = c),
                  ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (cat.faq.isNotEmpty) ...[
                  Text('常見問題',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink3)),
                  const SizedBox(height: 4),
                  for (final f in cat.faq)
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Q：${f.q}',
                            style: const TextStyle(fontSize: 13.5)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(f.a,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.6,
                                    color: AppColors.ink2)),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                ],
                Text('還是需要回報？填一下：',
                    style: TextStyle(fontSize: 13, color: AppColors.ink2)),
                const SizedBox(height: 12),
                if (cat.key == 'data') ...[
                  Text('哪個部分有問題？',
                      style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      for (final s in kDataSubtypes)
                        ChoiceChip(
                          label: Text(s),
                          selected: _subtype == s,
                          onSelected: (_) => setState(
                              () => _subtype = _subtype == s ? null : s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(
                        _stockCode == null
                            ? '帶入相關個股（選填）'
                            : '個股：$_stockName $_stockCode',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () async {
                        final r = await pickSymbol(context);
                        if (r != null) {
                          setState(() {
                            _stockCode = r.$1.code;
                            _stockName = r.$2;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text('照片${_images.isNotEmpty ? ' ${_images.length}' : ''}'),
                    onPressed: () async {
                      final imgs = await pickFeedbackImages();
                      if (imgs.isNotEmpty) setState(() => _images = imgs);
                    },
                  ),
                ]),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 68,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _images.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(base64Decode(_images[i]),
                                    width: 68, height: 68, fit: BoxFit.cover),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: InkWell(
                                  onTap: () => setState(
                                      () => _images.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectC,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: '主題（一句話說明）',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyC,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: '詳細內容（發生什麼、怎麼操作的）',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _contactC,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '聯絡方式（選填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('送出'),
                ),
                const SizedBox(height: 8),
                Text('送出後可在列表點進去看開發者回覆；開發者結案 10 天後雲端資料會刪除，'
                    '這支手機上的紀錄會保留。',
                    style: TextStyle(fontSize: 11, color: AppColors.ink3)),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 票券詳情：對話串 + 可追加訊息（未結案時）
// ---------------------------------------------------------------------------
class TicketDetailPage extends StatefulWidget {
  final FbTicket ticket;
  const TicketDetailPage({super.key, required this.ticket});
  @override
  State<TicketDetailPage> createState() => FbTicketDetailPageState();
}

class FbTicketDetailPageState extends State<TicketDetailPage> {
  final _c = TextEditingController();
  bool _sending = false;
  List<String> _fuImages = [];

  @override
  void initState() {
    super.initState();
    // 使用者實際點進來看了 → 標記已讀，清掉「新回覆」紅點
    _markSeen();
  }

  Future<void> _markSeen() async {
    final t = widget.ticket;
    final la = t.lastAdminAt;
    if (la <= t.seenAdminAt) return;
    t.seenAdminAt = la;
    if (t.notifiedAdminAt < la) t.notifiedAdminAt = la;
    await _persistLocal();
    await refreshFeedbackUnread();
  }

  Future<void> _addFollowUp() async {
    final text = _c.text.trim();
    if ((text.isEmpty && _fuImages.isEmpty) || _sending) return;
    if (!firebaseReady) return;
    setState(() => _sending = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      // 使用者又補了訊息 → 若正在等結案確認，退回處理中
      final reopen = widget.ticket.status == 'pending_user_close';
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.ticket.id)
          .update({
        'messages': FieldValue.arrayUnion([
          {
            'from': 'user',
            'text': text,
            'at': now,
            if (_fuImages.isNotEmpty) 'images': _fuImages,
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
        if (reopen) 'status': 'open',
        if (fcmToken != null) 'deviceToken': fcmToken,
      });
      if (reopen) widget.ticket.status = 'open';
      widget.ticket.messages
          .add(FbMsg('user', text, now, images: _fuImages));
      final ts = await loadFeedbackTickets();
      final idx = ts.indexWhere((x) => x.id == widget.ticket.id);
      if (idx >= 0) {
        ts[idx] = widget.ticket;
        await saveFeedbackTickets(ts);
      }
      _c.clear();
      _fuImages = [];
      if (mounted) FocusScope.of(context).unfocus();
      setState(() => _sending = false);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rate(int n) async {
    setState(() => widget.ticket.rating = n);
    try {
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.ticket.id)
          .update({'rating': n});
    } catch (_) {}
    await _persistLocal();
  }

  Future<void> _persistLocal() async {
    final ts = await loadFeedbackTickets();
    final idx = ts.indexWhere((x) => x.id == widget.ticket.id);
    if (idx >= 0) {
      ts[idx] = widget.ticket;
      await saveFeedbackTickets(ts);
    }
  }

  /// 使用者同意結案（開發者已問過「還有其他問題嗎」）
  Future<void> _agreeClose() async {
    if (!firebaseReady) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: const Text('確定沒有其他問題，結束這則反饋？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('還有問題')),
          TextButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('結案')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.ticket.id)
          .update({
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() => widget.ticket.status = 'closed');
      await _persistLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  /// 回應開發者「請補上是哪一檔股票」
  Future<void> _provideStock() async {
    final r = await pickSymbol(context);
    if (r == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.ticket.id)
          .update({
        'stockCode': r.$1.code,
        'stockName': r.$2,
        'needStock': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'messages': FieldValue.arrayUnion([
          {
            'from': 'user',
            'text': '補充相關個股：${r.$2} ${r.$1.code}',
            'at': DateTime.now().millisecondsSinceEpoch,
          }
        ]),
      });
      setState(() {
        widget.ticket.stockCode = r.$1.code;
        widget.ticket.stockName = r.$2;
        widget.ticket.needStock = false;
        widget.ticket.messages.add(FbMsg('user',
            '補充相關個股：${r.$2} ${r.$1.code}',
            DateTime.now().millisecondsSinceEpoch));
      });
      await _persistLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  /// 回應開發者「請補上截圖」
  Future<void> _providePhoto() async {
    final imgs = await pickFeedbackImages();
    if (imgs.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.ticket.id)
          .update({
        'needPhoto': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'messages': FieldValue.arrayUnion([
          {'from': 'user', 'text': '補上截圖', 'at': now, 'images': imgs}
        ]),
      });
      setState(() {
        widget.ticket.needPhoto = false;
        widget.ticket.messages
            .add(FbMsg('user', '補上截圖', now, images: imgs));
      });
      await _persistLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final closed = t.status == 'closed';
    final awaiting = t.status == 'pending_user_close';
    return Scaffold(
      appBar: AppBar(title: Text(t.subject)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: AppColors.surface2,
            child: Text(
              '${categoryOf(t.category).label} · 優先度 ${kPriorityLabel[t.priority]}'
              '${t.stockCode != null ? ' · 個股 ${t.stockName} ${t.stockCode}' : ''}'
              '${awaiting ? ' · 待你確認結案' : ''}'
              '${closed ? ' · 已結案' : ''}',
              style: TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final m in t.messages) _bubble(m),
                if (!closed && t.needStock && t.stockCode == null)
                  _requestCard(
                    icon: Icons.search,
                    text: '開發者想知道是哪一檔股票，方便直接查問題',
                    actionLabel: '指定個股',
                    onAction: _provideStock,
                  ),
                if (!closed && t.needPhoto)
                  _requestCard(
                    icon: Icons.add_a_photo_outlined,
                    text: '開發者希望你補一張出問題畫面的截圖',
                    actionLabel: '加截圖',
                    onAction: _providePhoto,
                  ),
                if (awaiting) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warn.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warn.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('開發者想結束這則反饋',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Text('如果沒有其他問題，按「同意結案」；還有想說的就直接在下面回覆。',
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: AppColors.ink2)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _agreeClose,
                                child: const Text('沒有其他問題，同意結案'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (closed) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                        t.rating > 0 ? '謝謝你的評分' : '此反饋已結案，這次的處理滿意嗎？',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.ink3)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final e in const [
                        (1, '😞'),
                        (2, '😐'),
                        (3, '😊'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: InkWell(
                            onTap: t.rating > 0 ? null : () => _rate(e.$1),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.rating == e.$1
                                    ? AppColors.accent
                                        .withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Text(e.$2,
                                  style: TextStyle(
                                      fontSize: 28,
                                      color: t.rating == 0 ||
                                              t.rating == e.$1
                                          ? null
                                          : AppColors.ink3)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!closed) ...[
            const Divider(height: 1),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      _fuImages.isEmpty
                          ? Icons.add_a_photo_outlined
                          : Icons.photo,
                      color: _fuImages.isEmpty ? null : AppColors.accent,
                    ),
                    tooltip: '附照片',
                    onPressed: () async {
                      final imgs = await pickFeedbackImages();
                      if (imgs.isNotEmpty) setState(() => _fuImages = imgs);
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '補充說明…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _addFollowUp,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('送出'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _requestCard({
    required IconData icon,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: AppColors.ink2)),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _bubble(FbMsg m) {
    final mine = m.from == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: mine
              ? null
              : Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text('開發者',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
            if (m.text.isNotEmpty)
              Text(m.text,
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: AppColors.ink)),
            for (final b64 in m.images)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      child: InteractiveViewer(
                        child: Image.memory(base64Decode(b64)),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(base64Decode(b64),
                        width: 180, fit: BoxFit.cover),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(_fmt(m.at),
                style: TextStyle(fontSize: 10.5, color: AppColors.ink3)),
          ],
        ),
      ),
    );
  }
}
