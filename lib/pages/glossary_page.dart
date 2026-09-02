import 'package:flutter/material.dart';
import '../glossary.dart';
import '../theme.dart';

/// 底部彈出：單一名詞解釋
void showTerm(BuildContext context, String key) {
  final text = glossaryLookup(key);
  if (text == null) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.menu_book_outlined,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(key,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  fontSize: 15, height: 1.7, color: AppColors.ink2)),
        ],
      ),
    ),
  );
}

/// 可點的「ⓘ」小圖示
class TermInfo extends StatelessWidget {
  final String term;
  const TermInfo(this.term, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showTerm(context, term),
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Icon(Icons.info_outline, size: 15, color: AppColors.ink3),
        ),
      );
}

class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key});
  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final entries = kGlossary.entries
        .where((e) =>
            _q.isEmpty || e.key.contains(_q) || e.value.contains(_q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
              hintText: '名詞小百科（搜尋：殖利率、KD、填息…）',
              border: InputBorder.none),
        ),
      ),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = entries[i];
          return ListTile(
            title: Text(e.key,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e.value,
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: AppColors.ink2)),
            ),
          );
        },
      ),
    );
  }
}
