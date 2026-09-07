import 'package:flutter/material.dart';
import '../glossary.dart';
import '../theme.dart';

/// 底部彈出：單一名詞解釋（有進階說明時可再展開「更詳細」）
void showTerm(BuildContext context, String key) {
  final text = glossaryLookup(key);
  if (text == null) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _TermSheet(term: key, text: text),
  );
}

class _TermSheet extends StatefulWidget {
  final String term;
  final String text;
  const _TermSheet({required this.term, required this.text});
  @override
  State<_TermSheet> createState() => _TermSheetState();
}

class _TermSheetState extends State<_TermSheet> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final detail = glossaryDetailLookup(widget.term);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.menu_book_outlined,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(widget.term,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            Text(widget.text,
                style: TextStyle(
                    fontSize: 15, height: 1.7, color: AppColors.ink2)),
            if (detail != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Text(_expanded ? '收合' : '更詳細',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent)),
                    Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: AppColors.accent),
                  ]),
                ),
              ),
              if (_expanded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(detail,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.75,
                          color: AppColors.ink2)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 可點的「ⓘ」小圖示
class TermInfo extends StatelessWidget {
  final String term;
  const TermInfo(this.term, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showTerm(context, term),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
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
          final hasDetail = glossaryDetailLookup(e.key) != null;
          return ListTile(
            onTap: () => showTerm(context, e.key),
            title: Text(e.key,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e.value,
                  style: TextStyle(
                      fontSize: 13, height: 1.6, color: AppColors.ink2)),
            ),
            trailing: hasDetail
                ? const Text('更詳細',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent))
                : null,
          );
        },
      ),
    );
  }
}
