import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
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
        title: const Text('自選股'),
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.swap_vert),
            onSelected: (m) =>
                ref.read(_sortProvider.notifier).state = m,
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.custom, child: Text('自訂順序')),
              PopupMenuItem(value: SortMode.changePct, child: Text('依漲跌幅')),
              PopupMenuItem(value: SortMode.price, child: Text('依股價')),
              PopupMenuItem(value: SortMode.volume, child: Text('依成交量')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
        ],
      ),
      body: list.isEmpty
          ? const _Empty()
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(quotesProvider.notifier).refresh(),
              child: sort == SortMode.custom
                  ? ReorderableListView.builder(
                      itemCount: sorted.length,
                      onReorder: (o, n) =>
                          ref.read(watchlistProvider.notifier).reorder(o, n),
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
              builder: (_) => QuoteDetailPage(symbol: s, name: q?.name ?? s.code)),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('尚無自選股，右上角 + 新增',
            style: TextStyle(color: AppColors.ink3)),
      );
}
