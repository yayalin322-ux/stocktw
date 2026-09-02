import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/universe_service.dart';
import '../services/yahoo_service.dart';
import '../state.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

/// 搜尋股票（台股代號/國字，或美股代號/名稱）。
/// pick=false：點結果直接進個股頁（純瀏覽，不加入自選）。
/// pick=true：回傳 (Symbol, name)。
class SearchPage extends ConsumerStatefulWidget {
  final bool pick;
  const SearchPage({super.key, this.pick = false});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl = TextEditingController();
  List<StockRef> _tw = [];
  List<StockRef> _us = [];
  bool _loadingUniverse = true;
  bool _searchingUS = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    universeService.ensureLoaded().then((_) {
      if (mounted) setState(() => _loadingUniverse = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {
      _tw = universeService.search(q);
      _us = [];
    });
    _debounce?.cancel();
    // 有英文字母 → 一併查美股
    if (RegExp(r'[A-Za-z]').hasMatch(q) && q.trim().length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 400), () async {
        setState(() => _searchingUS = true);
        final us = await yahooService.search(q.trim());
        if (!mounted) return;
        setState(() {
          _us = us;
          _searchingUS = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = [..._tw, ..._us];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: '2330、台積、金融 / AAPL、Nvidia',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _loadingUniverse && !universeService.ready
          ? const Center(child: CircularProgressIndicator())
          : results.isEmpty
              ? (_ctrl.text.isEmpty ? _hotEtf() : _emptyMsg())
              : ListView.separated(
                  itemCount: results.length + (_searchingUS ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i >= results.length) {
                      return const ListTile(
                        dense: true,
                        title: Text('搜尋美股中…',
                            style: TextStyle(color: AppColors.ink3)),
                      );
                    }
                    final r = results[i];
                    final inWatch =
                        ref.watch(watchlistProvider).contains(r.symbol);
                    return ListTile(
                      title: Row(children: [
                        Flexible(
                          child: Text(r.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (r.market == Market.us)
                          _badge('US', AppColors.accent),
                        if (r.market.isTW && isEtfCode(r.code))
                          _badge('ETF', AppColors.up),
                      ]),
                      subtitle: Text('${r.code} · ${r.market.label}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink3)),
                      trailing: widget.pick
                          ? const Icon(Icons.add)
                          : IconButton(
                              icon: Icon(
                                inWatch ? Icons.star : Icons.star_border,
                                color:
                                    inWatch ? AppColors.up : AppColors.ink3,
                              ),
                              onPressed: () {
                                final n =
                                    ref.read(watchlistProvider.notifier);
                                inWatch
                                    ? n.remove(r.symbol)
                                    : n.add(r.symbol);
                              },
                            ),
                      onTap: () {
                        if (widget.pick) {
                          Navigator.pop(context, (r.symbol, r.name));
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuoteDetailPage(
                                  symbol: r.symbol, name: r.name),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }

  Widget _badge(String t, Color c) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              color: c.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(4)),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10, color: c, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _emptyMsg() => Center(
        child: Text(_searchingUS ? '搜尋中…' : '查無結果',
            style: const TextStyle(color: AppColors.ink3)),
      );

  static const _hotEtfList = [
    ('0050', '元大台灣50'),
    ('0056', '元大高股息'),
    ('006208', '富邦台50'),
    ('00878', '國泰永續高股息'),
    ('00919', '群益台灣精選高息'),
    ('00929', '復華台灣科技優息'),
    ('00713', '元大台灣高息低波'),
    ('00940', '元大台灣價值高息'),
    ('00679B', '元大美債20年'),
    ('00757', '統一FANG+'),
    ('00646', '元大S&P500'),
    ('00662', '富邦NASDAQ'),
  ];

  Widget _hotEtf() {
    final recent = ref.watch(recentProvider);
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('輸入台股代號/國字，或美股代號/公司名',
              style: TextStyle(color: AppColors.ink3)),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('最近看過',
                style: TextStyle(
                    color: AppColors.ink3,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in recent)
                  ActionChip(
                    label: Text('${e.$1.code} ${e.$2}'),
                    onPressed: () {
                      if (widget.pick) {
                        Navigator.pop(context, (e.$1, e.$2));
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                QuoteDetailPage(symbol: e.$1, name: e.$2),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const Text('熱門 ETF',
              style: TextStyle(
                  color: AppColors.ink3,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _hotEtfList)
                ActionChip(
                  label: Text('${e.$1} ${e.$2}'),
                  onPressed: () {
                    final s = Symbol(e.$1, Market.tse);
                    if (widget.pick) {
                      Navigator.pop(context, (s, e.$2));
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              QuoteDetailPage(symbol: s, name: e.$2),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ],
      );
  }
}

Future<(Symbol, String)?> pickSymbol(BuildContext context) {
  return Navigator.push<(Symbol, String)?>(
    context,
    MaterialPageRoute(builder: (_) => const SearchPage(pick: true)),
  );
}
