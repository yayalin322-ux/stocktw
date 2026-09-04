import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market_service.dart';
import '../widgets.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

const _kinds = [
  ('gain', '漲幅', '%'),
  ('lose', '跌幅', '%'),
  ('value', '成交值', '億'),
  ('yield', '高殖利率', '%'),
  ('pe', '低本益比', ''),
];

class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key});
  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: _kinds.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選股排行'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.ink,
          unselectedLabelColor: AppColors.ink3,
          indicatorColor: AppColors.accent,
          tabs: [for (final k in _kinds) Tab(text: k.$2)],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [for (final k in _kinds) _RankList(kind: k.$1, unit: k.$3)],
      ),
    );
  }
}

class _RankList extends StatefulWidget {
  final String kind;
  final String unit;
  const _RankList({required this.kind, required this.unit});
  @override
  State<_RankList> createState() => _RankListState();
}

class _RankListState extends State<_RankList>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Ranked>> _f = marketService.ranking(widget.kind);
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _f = marketService.ranking(widget.kind));
        await _f;
      },
      child: FutureBuilder<List<Ranked>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return Center(
                child: Text('查無資料', style: TextStyle(color: AppColors.ink3)));
          }
          final maxAbs = rows
              .map((e) => e.value.abs())
              .fold<double>(1, (a, b) => a > b ? a : b);
          final diverging = widget.kind == 'gain' || widget.kind == 'lose';
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuoteDetailPage(
                        symbol: Symbol(r.code, Market.tse), name: r.name),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                        width: 26,
                        child: Text('${i + 1}',
                            style:
                                kNum.copyWith(color: AppColors.ink3))),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r.name}  ${r.code}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          if (r.price != null)
                            RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                    text: '收 ',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.ink3)),
                                TextSpan(
                                  text: r.price!.toStringAsFixed(2),
                                  style: kNum.copyWith(
                                      fontSize: 15,
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w700),
                                ),
                                TextSpan(
                                    text: ' 元',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.ink3)),
                              ]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: diverging
                          ? DivergingBar(r.value, maxAbs)
                          : RatioBar(r.value / maxAbs),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 68,
                      child: Text(
                        diverging
                            ? '${signed(r.value, 2)}%'
                            : '${r.value.toStringAsFixed(2)}${widget.unit}',
                        textAlign: TextAlign.right,
                        style: kNum.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: diverging
                              ? AppColors.forChange(r.value)
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
