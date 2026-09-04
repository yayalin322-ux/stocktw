import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'qr_export_page.dart';
import 'qr_scan_page.dart';
import 'quote_detail_page.dart';
import 'search_page.dart';

enum SortMode { custom, changePct, price, volume }

final _sortProvider = StateProvider<SortMode>((_) => SortMode.custom);

class WatchlistPage extends ConsumerWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(watchlistProvider);
    final quotes = ref.watch(quotesProvider);
    final sort = ref.watch(_sortProvider);
    final wl = ref.read(watchlistProvider.notifier);

    final sorted = [...list];
    int cmpNum(num? a, num? b) => (b ?? -1e18).compareTo(a ?? -1e18);
    if (sort != SortMode.custom) {
      sorted.sort((a, b) {
        final qa = quotes[a.id], qb = quotes[b.id];
        switch (sort) {
          case SortMode.changePct:
            return cmpNum(qa?.changePct, qb?.changePct);
          case SortMode.price:
            return cmpNum(qa?.price, qb?.price);
          case SortMode.volume:
            return cmpNum(qa?.volume, qb?.volume);
          case SortMode.custom:
            return 0;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _groupSheet(context, ref),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(wl.currentGroup),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
        ),
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.swap_vert),
            onSelected: (m) => ref.read(_sortProvider.notifier).state = m,
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.custom, child: Text('自訂順序')),
              PopupMenuItem(value: SortMode.changePct, child: Text('依漲跌幅')),
              PopupMenuItem(value: SortMode.price, child: Text('依股價')),
              PopupMenuItem(value: SortMode.volume, child: Text('依成交量')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'QR 分享／匯入',
            onPressed: () => _qrSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
        ],
      ),
      body: list.isEmpty
          ? _Empty(onAdd: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SearchPage())))
          : RefreshIndicator(
              onRefresh: () => ref.read(quotesProvider.notifier).refresh(),
              child: sort == SortMode.custom
                  ? ReorderableListView.builder(
                      itemCount: sorted.length,
                      onReorder: (o, n) => wl.reorder(o, n),
                      itemBuilder: (c, i) => _row(context, ref, sorted[i],
                          quotes[sorted[i].id], key: ValueKey(sorted[i].id)),
                    )
                  : ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (c, i) => _row(
                          context, ref, sorted[i], quotes[sorted[i].id],
                          key: ValueKey(sorted[i].id)),
                    ),
            ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Symbol s, Quote? q,
      {required Key key}) {
    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.down,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(watchlistProvider.notifier).remove(s),
      child: QuoteRow(
        code: s.code,
        name: q?.name ?? '',
        q: q,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  QuoteDetailPage(symbol: s, name: q?.name ?? s.code)),
        ),
        onLongPress: () => _rowSheet(context, ref, s, q?.name ?? s.code),
      ),
    );
  }

  // QR 分享 / 掃描匯入
  void _qrSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_2, color: AppColors.accent),
              title: const Text('產生 QR 碼分享'),
              subtitle: const Text('把自選股、持倉編成 QR 給別人掃（可選要匯出哪些）',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const QrExportPage()));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.qr_code_scanner, color: AppColors.accent),
              title: const Text('掃描 QR 碼匯入'),
              subtitle: const Text('把別人分享的資料加進來（可選要匯入哪些，不會覆蓋現有資料）',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const QrScanPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _groupSheet(BuildContext context, WidgetRef ref) {
    final wl = ref.read(watchlistProvider.notifier);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (c, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('自選群組',
                      style: TextStyle(
                          color: AppColors.ink2,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              for (final g in wl.groupNames)
                ListTile(
                  leading: Icon(
                    g == wl.currentGroup
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: g == wl.currentGroup
                        ? AppColors.accent
                        : AppColors.ink3,
                    size: 20,
                  ),
                  title: Text(g),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${wl.countOf(g)}',
                        style: TextStyle(
                            color: AppColors.ink3, fontSize: 12)),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (v) async {
                        if (v == 'rename') {
                          final name = await _askName(context, '改名群組', g);
                          if (name != null) {
                            wl.renameGroup(g, name);
                            setSheet(() {});
                          }
                        } else if (v == 'delete') {
                          wl.removeGroup(g);
                          setSheet(() {});
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename', child: Text('改名')),
                        if (wl.groupNames.length > 1)
                          const PopupMenuItem(
                              value: 'delete', child: Text('刪除群組')),
                      ],
                    ),
                  ]),
                  onTap: () {
                    wl.switchGroup(g);
                    Navigator.pop(c);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add, color: AppColors.accent),
                title: const Text('新增群組'),
                onTap: () async {
                  final name = await _askName(context, '新增群組', '');
                  if (name != null) {
                    wl.addGroup(name);
                    setSheet(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 個股長按：移動到其他群組 / 刪除
  void _rowSheet(
      BuildContext context, WidgetRef ref, Symbol s, String name) {
    final wl = ref.read(watchlistProvider.notifier);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$name  移動到…',
                    style: TextStyle(
                        color: AppColors.ink2, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final g in wl.groupNames)
              if (g != wl.currentGroup)
                ListTile(
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: Text(g),
                  onTap: () {
                    wl.moveToGroup(s, g);
                    Navigator.pop(context);
                  },
                ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.down),
              title: const Text('從自選移除'),
              onTap: () {
                wl.remove(s);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(
      BuildContext context, String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(
              hintText: '群組名稱', counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('確定')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('這個群組還沒有股票',
                style: TextStyle(color: AppColors.ink3)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('搜尋新增'),
            ),
          ],
        ),
      );
}
