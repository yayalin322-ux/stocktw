import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:k_chart_plus/k_chart_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/candle_service.dart';
import '../services/market_service.dart';
import '../services/financials_service.dart';
import '../services/fundamentals_service.dart';
import '../services/news_service.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../etf_holdings.dart';
import '../glossary.dart';
import 'alerts_page.dart';
import 'compare_page.dart';
import 'glossary_page.dart';
import 'portfolio_page.dart';

const _periods = {
  '分時': ('1d', '1m'),
  '5分': ('5d', '5m'),
  '15分': ('5d', '15m'),
  '30分': ('1mo', '30m'),
  '60分': ('3mo', '60m'),
  '日K': ('1y', '1d'),
  '週K': ('5y', '1wk'),
  '月K': ('max', '1mo'),
};

KChartColors _kchartColors() => KChartColors(
      bgColor: AppColors.bg,
      upColor: AppColors.up,
      dnColor: AppColors.down,
      volUpColor: AppColors.up,
      volDnColor: AppColors.down,
      nowPriceUpColor: AppColors.up,
      nowPriceDnColor: AppColors.down,
      gridColor: AppColors.border,
      defaultTextColor: AppColors.ink2,
      maxColor: AppColors.ink2,
      minColor: AppColors.ink2,
      crossColor: AppColors.ink,
      crossTextColor: AppColors.ink,
      // 長按十字線的價格/日期小標籤：套件預設是白底，暗色主題下會變成
      // 兩個突兀的白色方塊，這裡改成跟卡片同色的底 + 邊框。
      selectFillColor: AppColors.surface2,
      selectBorderColor: AppColors.border,
    );

String _yi(double? thousand) =>
    thousand == null ? '--' : '${(thousand / 1e5).toStringAsFixed(1)} 億';
String _rocDate(String? s) {
  if (s == null || s.length < 7) return s ?? '--';
  // 支援 19940905 或 民國格式
  if (s.length == 8) return '${s.substring(0, 4)}/${s.substring(4, 6)}/${s.substring(6)}';
  return s;
}

class QuoteDetailPage extends ConsumerStatefulWidget {
  final Symbol symbol;
  final String name;
  const QuoteDetailPage({super.key, required this.symbol, required this.name});
  @override
  ConsumerState<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends ConsumerState<QuoteDetailPage>
    with SingleTickerProviderStateMixin {
  final List<MainIndicator> _mainInd = [
    MAIndicator(),
    EMAIndicator(),
    BOLLIndicator(),
    SARIndicator(),
  ];
  final List<SecondaryIndicator> _secInd = [
    MACDIndicator(),
    KDJIndicator(),
    RSIIndicator(),
    WRIndicator(),
    CCIIndicator(),
  ];
  final _mainSel = <int>{0};
  final _secSel = <int>{0};

  String _period = '日K';
  List<KLineEntity>? _entities;
  Intraday? _intraday;
  Map<String, double>? _cdp; // 分時圖 CDP 壓力/支撐
  bool _loadingChart = true;
  String? _chartErr;
  Profile? _profile;

  bool get _isTW => widget.symbol.market.isTW;
  bool get _isEtf => _isTW && isEtfCode(widget.symbol.code);
  bool get _hasHoldings => kEtfHoldings.containsKey(widget.symbol.code);
  // 一般台股：五檔/財報/股利/籌碼/相關/新聞
  // ETF：五檔/(成分股)/股利/籌碼/相關/新聞（無財報）
  // 美股：新聞
  int get _tabCount => (_isTW
          ? (_isEtf ? (_hasHoldings ? 5 : 4) : 5) + 1 // + 相關
          : 1) +
      1; // + 備忘錄
  late final TabController _tab = TabController(length: _tabCount, vsync: this);

  @override
  void initState() {
    super.initState();
    // 切換動畫結束後再動 provider，避免「build 期間修改 provider」錯誤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(quotesProvider.notifier).subscribe(widget.symbol);
      ref.read(recentProvider.notifier).add(widget.symbol, widget.name);
    });
    _loadChart();
    if (_isTW && !_isEtf) {
      financialsService.profile(widget.symbol.code).then((p) {
        if (mounted) setState(() => _profile = p);
      });
    }
  }

  Future<void> _loadChart() async {
    setState(() {
      _loadingChart = true;
      _chartErr = null;
    });
    try {
      final (range, interval) = _periods[_period]!;
      if (_period == '分時') {
        final sym =
            '${widget.symbol.code}${widget.symbol.market.yahooSuffix}';
        final id = await marketService.intraday(sym);
        setState(() {
          _intraday = id;
          _loadingChart = false;
        });
        _loadCdp();
        return;
      }
      final candles = await candleService.fetch(widget.symbol,
          range: range, interval: interval);
      final e = candles
          .map((c) => KLineEntity.fromCustom(
                time: c.time.millisecondsSinceEpoch,
                open: c.open,
                high: c.high,
                low: c.low,
                close: c.close,
                vol: c.volume,
                amount: c.volume * c.close,
              ))
          .toList();
      DataUtil.calculateAll(e, _mainInd, _secInd);
      setState(() {
        _entities = e;
        _loadingChart = false;
      });
    } catch (err) {
      setState(() {
        _chartErr = '$err';
        _loadingChart = false;
      });
    }
  }

  /// 用昨日 高/低/收 算 CDP 逆勢操作點位，畫在分時圖上
  Future<void> _loadCdp() async {
    try {
      final daily = await candleService.fetch(widget.symbol,
          range: '1mo', interval: '1d');
      int key(DateTime d) {
        final t = d.toUtc().add(const Duration(hours: 8)); // 台北
        return t.year * 10000 + t.month * 100 + t.day;
      }

      final todayKey = key(DateTime.now());
      final prev = daily.where((c) => key(c.time) < todayKey).toList();
      if (prev.isEmpty) return;
      final d = prev.last;
      final h = d.high, l = d.low, cl = d.close;
      final cdp = (h + l + 2 * cl) / 4;
      final map = {
        '壓力²': cdp + (h - l),
        '壓力¹': 2 * cdp - l,
        '參考': cdp,
        '支撐¹': 2 * cdp - h,
        '支撐²': cdp - (h - l),
      };
      if (mounted && _period == '分時') setState(() => _cdp = map);
    } catch (_) {
      // 靜默
    }
  }

  void _openFullscreen() {
    final es = _entities;
    if (es == null || es.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _KChartFullscreen(
        entities: es,
        main: _mainSel.map((i) => _mainInd[i]).toList(),
        secondary: _secSel.map((i) => _secInd[i]).toList(),
        title: '${widget.name} ${widget.symbol.code} · $_period',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(quoteProvider(widget.symbol));
    ref.watch(watchlistProvider); // 群組任何變動都重繪星號
    final inWatch =
        ref.read(watchlistProvider.notifier).containsAnywhere(widget.symbol);
    final name = q?.name ?? widget.name;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(name),
          const SizedBox(width: 8),
          Text(widget.symbol.code,
              style: const TextStyle(color: AppColors.ink3, fontSize: 13)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '名詞小百科',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GlossaryPage())),
          ),
          IconButton(
            icon: Icon(inWatch ? Icons.star : Icons.star_border,
                color: inWatch ? AppColors.up : null),
            onPressed: () {
              final n = ref.read(watchlistProvider.notifier);
              inWatch ? n.remove(widget.symbol) : n.add(widget.symbol);
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          _header(q),
          _periodBar(),
          Stack(
            children: [
              SizedBox(height: 360, child: _chart()),
              if (_period != '分時' &&
                  _entities != null &&
                  _entities!.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: AppColors.surface2.withValues(alpha: 0.8),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen, size: 20),
                      color: AppColors.ink2,
                      tooltip: '全螢幕橫向',
                      onPressed: _openFullscreen,
                    ),
                  ),
                ),
            ],
          ),
          if (_period != '分時') ...[
            _indicatorBar(),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 2),
              child: Text('雙指縮放 K 線 · 長按看每根詳細 · 右上可全螢幕',
                  style: TextStyle(fontSize: 10, color: AppColors.ink3)),
            ),
          ],
          const SizedBox(height: 8),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.ink3,
            indicatorColor: AppColors.accent,
            tabs: [
              if (_isTW) const Tab(text: '五檔'),
              if (_isTW && !_isEtf) const Tab(text: '財報'),
              if (_isEtf && _hasHoldings) const Tab(text: '成分股'),
              if (_isTW) const Tab(text: '股利/配息'),
              if (_isTW) const Tab(text: '籌碼'),
              if (_isTW) const Tab(text: '相關'),
              const Tab(text: '新聞'),
              const Tab(text: '備忘錄'),
            ],
          ),
          SizedBox(
            height: 420,
            child: TabBarView(
              controller: _tab,
              children: [
                if (_isTW) _orderBook(q),
                if (_isTW && !_isEtf)
                  _FinancialsTab(code: widget.symbol.code),
                if (_isEtf && _hasHoldings)
                  _HoldingsTab(code: widget.symbol.code),
                if (_isTW)
                  _DividendTab(code: widget.symbol.code, price: q?.price),
                if (_isTW) _ChipTab(code: widget.symbol.code),
                if (_isTW)
                  _RelatedTab(symbol: widget.symbol, name: name),
                _NewsTab(
                    code: widget.symbol.code, name: name, tw: _isTW),
                _NotesTab(id: widget.symbol.id),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('到價提醒'),
                onPressed: () =>
                    showAddAlert(context, ref, widget.symbol, name, price: q?.price),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_chart, size: 18),
                label: const Text('記錄持倉'),
                onPressed: () => showAddPosition(context, ref, widget.symbol, name),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(Quote? q) {
    final p = _profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PriceText(q?.price, q?.change, size: 34),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ChangeText(q?.change, q?.changePct, size: 15),
              ),
              const Spacer(),
              if (q?.isLimitUp == true) const LimitBadge(true),
              if (q?.isLimitDown == true) const LimitBadge(false),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 6, children: [
            _kv('開', q?.open),
            _kv('高', q?.high),
            _kv('低', q?.low),
            _kv('昨收', q?.prevClose),
            _kv('量(張)', q?.volume.toDouble(), dp: 0),
          ]),
          if (p != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (p.industry != null) _chip(p.industry!),
              if (p.capital != null)
                _chip('資本額 ${(p.capital! / 1e8).toStringAsFixed(0)} 億'),
              if (p.listedDate != null) _chip('上市 ${_rocDate(p.listedDate)}'),
              if (p.chairman != null) _chip('董座 ${p.chairman}'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border)),
        child: Text(t,
            style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
      );

  Widget _kv(String k, double? v, {int dp = 2}) => RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$k ',
              style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
          TextSpan(
            text: v == null ? '--' : v.toStringAsFixed(dp),
            style: kNum.copyWith(fontSize: 13, color: AppColors.ink),
          ),
        ]),
      );

  Widget _periodBar() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _periods.keys.map((p) {
          final on = p == _period;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: Text(p),
              selected: on,
              onSelected: (_) {
                setState(() => _period = p);
                _loadChart();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _chart() {
    if (_loadingChart) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_period == '分時') {
      final id = _intraday;
      final c = id?.points ?? const <Candle>[];
      final q = ref.read(quoteProvider(widget.symbol));
      final prev = q?.prevClose ??
          id?.prevClose ??
          (c.isNotEmpty ? c.first.open : 0).toDouble();
      return IntradayChart(
        c.map((e) => e.close).toList(),
        c.map((e) => e.volume).toList(),
        prev,
        times: c.map((e) => e.time.millisecondsSinceEpoch ~/ 1000).toList(),
        regStart: id?.regStart,
        regEnd: id?.regEnd,
        cdp: _cdp ?? const {},
      );
    }
    if (_chartErr != null || _entities == null || _entities!.isEmpty) {
      return Center(
        child: Text('K 線載入失敗\n${_chartErr ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink3)),
      );
    }
    return KChartWidget(
      _entities,
      const KChartStyle(),
      _kchartColors(),
      isTrendLine: false,
      mainIndicators: _mainSel.map((i) => _mainInd[i]).toList(),
      secondaryIndicators: _secSel.map((i) => _secInd[i]).toList(),
      mBaseHeight: 230,
      mSecondaryHeight: 70,
      fixedLength: 2,
      timeFormat: _period.contains('分')
          ? TimeFormat.YEAR_MONTH_DAY_WITH_HOUR
          : TimeFormat.YEAR_MONTH_DAY,
      detailBuilder: (e) => Container(
        padding: const EdgeInsets.all(8),
        color: AppColors.surface2,
        child: Text(
          '開 ${e.open.toStringAsFixed(2)}  高 ${e.high.toStringAsFixed(2)}\n'
          '低 ${e.low.toStringAsFixed(2)}  收 ${e.close.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 11, color: AppColors.ink),
        ),
      ),
    );
  }

  static const _indDesc = {
    'MA': 'MA均線',
    'EMA': 'EMA',
    'BOLL': 'BOLL布林通道',
    'SAR': 'SAR',
    'MACD': 'MACD',
    'KDJ': 'KD',
    'RSI': 'RSI',
    'WR': 'WR威廉指標',
    'CCI': 'CCI',
  };

  Widget _indicatorBar() {
    final active = [
      ..._mainSel.map((i) => _mainInd[i].shortName),
      ..._secSel.map((i) => _secInd[i].shortName),
    ].join('、');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('指標'),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact),
            onPressed: _openIndicatorSheet,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(active.isEmpty ? '未開啟指標' : active,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _openIndicatorSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSt) {
          Widget tile(String name, bool on, VoidCallback toggle) {
            final term = _indDesc[name] ?? name;
            return SwitchListTile(
              dense: true,
              value: on,
              onChanged: (_) {
                setSt(toggle);
                setState(() {});
              },
              title: Row(children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                TermInfo(term),
              ]),
              subtitle: Text(glossaryLookup(term) ?? '',
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            );
          }

          // 小螢幕內容可能比可視高度長，固定一個上限高度＋常駐關閉鈕，
          // 避免像之前那樣被撐到滿版、找不到地方可以關掉。
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                  child: Row(
                    children: [
                      const Text('選擇指標',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text('主圖指標',
                            style: TextStyle(
                                color: AppColors.ink3,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      for (var i = 0; i < _mainInd.length; i++)
                        tile(_mainInd[i].shortName, _mainSel.contains(i),
                            () => _mainSel.contains(i)
                                ? _mainSel.remove(i)
                                : _mainSel.add(i)),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text('副圖指標（圖表下方）',
                            style: TextStyle(
                                color: AppColors.ink3,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      for (var i = 0; i < _secInd.length; i++)
                        tile(_secInd[i].shortName, _secSel.contains(i),
                            () => _secSel.contains(i)
                                ? _secSel.remove(i)
                                : _secSel.add(i)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _orderBook(Quote? q) {
    if (q == null || (q.bids.isEmpty && q.asks.isEmpty)) {
      return const Center(
          child: Text('無五檔資料（非交易時段）',
              style: TextStyle(color: AppColors.ink3)));
    }
    final maxQty = [
      ...q.bids.map((e) => e.qty),
      ...q.asks.map((e) => e.qty),
      1,
    ].reduce((a, b) => a > b ? a : b);

    Widget level(PriceQty l, bool bid) {
      final w = (l.qty / maxQty).clamp(0.0, 1.0);
      final c = bid ? AppColors.up : AppColors.down;
      return Stack(children: [
        Align(
          alignment: bid ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: w,
            child: Container(height: 30, color: c.withValues(alpha: 0.12)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(bid ? '${l.qty}' : l.price.toStringAsFixed(2),
                  style: kNum.copyWith(
                      color: bid ? AppColors.ink2 : c, fontSize: 13)),
              Text(bid ? l.price.toStringAsFixed(2) : '${l.qty}',
                  style: kNum.copyWith(
                      color: bid ? c : AppColors.ink2, fontSize: 13)),
            ],
          ),
        ),
      ]);
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('買量 / 買價', style: TextStyle(color: AppColors.ink3, fontSize: 12)),
            Text('賣價 / 賣量', style: TextStyle(color: AppColors.ink3, fontSize: 12)),
          ]),
        ),
        for (final l in q.asks.reversed) level(l, false),
        const Divider(),
        for (final l in q.bids) level(l, true),
      ],
    );
  }

  @override
  void dispose() {
    ref.read(quotesProvider.notifier).unsubscribe(widget.symbol);
    _tab.dispose();
    super.dispose();
  }
}

// ---------------- 財報 ----------------
class _FinancialsTab extends StatelessWidget {
  final String code;
  const _FinancialsTab({required this.code});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        financialsService.revenue(code),
        financialsService.income(code),
      ]),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rev = snap.data?[0] as Revenue?;
        final inc = snap.data?[1] as Income?;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _H('月營收'),
            if (rev == null)
              const _Empty()
            else ...[
              _row('資料月份', rev.ym),
              _row('當月營收', _yi(rev.month)),
              _row('去年同月增減', rev.yoy == null ? '--' : '${signed(rev.yoy!, 1)}%',
                  c: rev.yoy == null ? null : AppColors.forChange(rev.yoy!),
                  term: '營收年增率'),
              _row('累計營收年增', rev.accYoy == null ? '--' : '${signed(rev.accYoy!, 1)}%',
                  c: rev.accYoy == null
                      ? null
                      : AppColors.forChange(rev.accYoy!)),
            ],
            const SizedBox(height: 22),
            const _H('損益表（單季）'),
            if (inc == null)
              const _Empty()
            else ...[
              _row('期別', inc.period),
              _row('營業收入', _yi(inc.revenue)),
              _row('營業毛利', _yi(inc.grossProfit)),
              _row('毛利率',
                  inc.grossMargin == null
                      ? '--'
                      : '${inc.grossMargin!.toStringAsFixed(1)}%',
                  term: '毛利率'),
              _row('營業利益', _yi(inc.opIncome)),
              _row('稅後淨利', _yi(inc.netIncome)),
              _row('淨利率',
                  inc.netMargin == null
                      ? '--'
                      : '${inc.netMargin!.toStringAsFixed(1)}%',
                  term: '淨利率'),
              _row('EPS（元）', inc.eps?.toStringAsFixed(2) ?? '--',
                  c: inc.eps == null ? null : AppColors.forChange(inc.eps!),
                  term: 'EPS'),
            ],
          ],
        );
      },
    );
  }
}

// ---------------- 股利 / 除權息 ----------------
class _DividendTab extends StatelessWidget {
  final String code;
  final double? price;
  const _DividendTab({required this.code, this.price});

  String _roc(String s) {
    // 115年09月07日 → 民國114/09/07；或 yyyyMMdd
    final m = RegExp(r'(\d+)年(\d+)月(\d+)日').firstMatch(s);
    if (m != null) return '民國${m[1]}/${m[2]}/${m[3]}';
    if (s.length == 8) {
      return '${s.substring(0, 4)}/${s.substring(4, 6)}/${s.substring(6)}';
    }
    return s.isEmpty ? '未定' : s;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        financialsService.dividends(code),
        financialsService.exDividend(code),
        financialsService.dividendHistory(code, true),
      ]),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = (snap.data?[0] as List<DividendRow>?) ?? const [];
        final ex = snap.data?[1] as ExDividend?;
        final hist =
            (snap.data?[2] as List<YearDividend>?) ?? const <YearDividend>[];
        if (rows.isEmpty && ex == null && hist.isEmpty) return const _Empty();

        final maxHist = hist.isEmpty
            ? 1.0
            : hist.map((e) => e.cash).reduce((a, b) => a > b ? a : b);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 即將除權息
            if (ex != null) ...[
              Row(children: const [
                _H('即將除權息'),
                SizedBox(width: 4),
                TermInfo('除息'),
              ]),
              _row('除權息交易日', _roc(ex.exDate), term: '除息'),
              _row('類型', ex.kind == '息'
                  ? '除息（配現金）'
                  : ex.kind == '權'
                      ? '除權（配股票）'
                      : '除權息'),
              _row('現金股利', '${ex.cash.toStringAsFixed(2)} 元/股', term: '現金股利'),
              if (ex.stockRate > 0)
                _row('無償配股率', ex.stockRate.toStringAsFixed(3),
                    term: '股票股利'),
              _row('除息參考價（試算）',
                  ex.refPrice?.toStringAsFixed(2) ?? '--', term: '除息參考價'),
              if (price != null && ex.refPrice != null)
                _row(
                  '填息進度',
                  _fillStatus(price!, ex.refPrice!, ex.cash),
                  c: price! >= ex.refPrice! + ex.cash
                      ? AppColors.up
                      : AppColors.ink2,
                  term: '填息',
                ),
              const SizedBox(height: 8),
              Text('備註：發放日通常在除息後約 1 個月，實際以公司公告為準。',
                  style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
              const SizedBox(height: 20),
            ],

            // 現金股利歷史
            if (hist.isNotEmpty) ...[
              Row(children: const [
                _H('近年現金股利'),
                SizedBox(width: 4),
                TermInfo('現金股利'),
              ]),
              for (final y in hist)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                        width: 44,
                        child: Text('${y.year}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.ink3))),
                    Expanded(
                      child: LayoutBuilder(builder: (_, cns) {
                        return Container(
                          height: 16,
                          width: (y.cash / maxHist) * cns.maxWidth,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    Text('${y.cash.toStringAsFixed(2)} 元',
                        style: kNum.copyWith(fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 20),
            ],

            // 股利政策（最新董事會/股東會決議）
            for (final d in rows.take(3)) ...[
              _H('${d.year} 年度股利政策 · ${d.period}'),
              _row('現金股利', '${d.cash.toStringAsFixed(2)} 元/股', term: '現金股利'),
              _row('股票股利', '${d.stock.toStringAsFixed(2)} 元/股', term: '股票股利'),
              _row('合計', '${(d.cash + d.stock).toStringAsFixed(2)} 元/股'),
              _row('決議進度', d.progress),
              if (d.agmDate.isNotEmpty) _row('股東會日期', _roc(d.agmDate)),
              const SizedBox(height: 18),
            ],

            // 紀念品
            Row(children: const [
              _H('股東會紀念品'),
              SizedBox(width: 4),
              TermInfo('股東會紀念品'),
            ]),
            const Text(
              '需在「停止過戶日」前持有並圈存，才有領取資格。'
              '實際品項、發放地點與時間依各公司股務公告為準，'
              '開放資料未提供，可至公司或股務代理（如群益、元大、中信）網站查詢。',
              style: TextStyle(fontSize: 12, height: 1.7, color: AppColors.ink3),
            ),
          ],
        );
      },
    );
  }

  String _fillStatus(double px, double ref, double cash) {
    final target = ref + cash; // 除息前價位
    if (px >= target) return '已填息 ✓';
    final need = target - px;
    return '差 ${need.toStringAsFixed(2)} 元填息';
  }
}

// ---------------- ETF 成分股 ----------------
class _HoldingsTab extends StatelessWidget {
  final String code;
  const _HoldingsTab({required this.code});
  @override
  Widget build(BuildContext context) {
    final hs = kEtfHoldings[code] ?? const [];
    final isUsEtf = code == '00646' || code == '00662';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('這裡收錄前 ${hs.length} 大成分股（權重近似，$kEtfAsOf；每季調整，以投信公告為準）',
            style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => launchUrl(
            Uri.parse(
                'https://www.google.com/search?q=${Uri.encodeComponent('$code 成分股 完整清單')}'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('查看完整成分股清單（投信官網）→',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        for (final h in hs)
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuoteDetailPage(
                  symbol: Symbol(
                      h.code, isUsEtf ? Market.us : Market.tse),
                  name: h.name,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                SizedBox(
                    width: 56,
                    child: Text(h.code,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.ink3))),
                SizedBox(
                  width: 92,
                  child: Text(h.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: RatioBar(h.weight / hs.first.weight, height: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text('${h.weight.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: kNum.copyWith(fontSize: 13)),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

// ---------------- 籌碼 / 估值 ----------------
class _ChipTab extends StatelessWidget {
  final String code;
  const _ChipTab({required this.code});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        fundamentalsService.fetch(code),
        financialsService.margin(code),
      ]),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final f = snap.data?[0] as Fundamentals?;
        final mg = snap.data?[1] as MarginInfo?;
        if (f == null && mg == null) return const _Empty();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (f != null) ...[
              const _H('估值'),
              _row('本益比 (PER)', f.per?.toStringAsFixed(2) ?? '--',
                  term: '本益比'),
              _row('股價淨值比 (PBR)', f.pbr?.toStringAsFixed(2) ?? '--',
                  term: '股價淨值比'),
              _row('殖利率', f.yield_ != null ? '${f.yield_}%' : '--',
                  term: '殖利率'),
              const SizedBox(height: 22),
              const _H('三大法人買賣超（前一交易日，張）'),
              _instBar('外資', f.foreignNet, f),
              _instBar('投信', f.trustNet, f),
              _instBar('自營商', f.dealerNet, f),
            ],
            if (mg != null) ...[
              const SizedBox(height: 22),
              const _H('融資融券（前一交易日）'),
              _row('融資餘額', '${nf0.format(mg.financeBal)} 張', term: '融資'),
              _row('融資增減', '${signed(mg.financeChg, 0)} 張',
                  c: AppColors.forChange(mg.financeChg)),
              _row('融券餘額', '${nf0.format(mg.shortBal)} 張', term: '融券'),
              _row('融券增減', '${signed(mg.shortChg, 0)} 張',
                  c: AppColors.forChange(mg.shortChg)),
              _row('券資比', '${mg.shortRatio.toStringAsFixed(2)}%'),
            ],
          ],
        );
      },
    );
  }

  Widget _instBar(String name, int? shares, Fundamentals f) {
    final v = (shares ?? 0) / 1000.0; // 張
    final mx = [
      (f.foreignNet ?? 0).abs(),
      (f.trustNet ?? 0).abs(),
      (f.dealerNet ?? 0).abs(),
      1,
    ].reduce((a, b) => a > b ? a : b) /
        1000.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
            width: 48,
            child: Text(name, style: const TextStyle(fontSize: 13))),
        Expanded(child: DivergingBar(v, mx)),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(shares == null ? '--' : signed(v, 0),
              textAlign: TextAlign.right,
              style: kNum.copyWith(
                  fontSize: 13, color: AppColors.forChange(v))),
        ),
      ]),
    );
  }
}

// ---------------- 新聞 ----------------
class _NewsTab extends StatelessWidget {
  final String code;
  final String name;
  final bool tw;
  const _NewsTab({required this.code, required this.name, this.tw = true});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NewsItem>>(
      future: newsService.fetch(code, name, tw: tw),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) return const _Empty();
        final fmt = DateFormat('MM/dd HH:mm');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final n = items[i];
            return ListTile(
              title: Text(n.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '${n.source}${n.published != null ? ' · ${fmt.format(n.published!.toLocal())}' : ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
              onTap: () => launchUrl(Uri.parse(n.url),
                  mode: LaunchMode.externalApplication),
            );
          },
        );
      },
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.ink3,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 30),
        child: Center(
            child: Text('查無資料', style: TextStyle(color: AppColors.ink3))),
      );
}

Widget _row(String k, String v, {Color? c, String? term}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(children: [
              Flexible(
                  child: Text(k,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14))),
              if (term != null) ...[
                const SizedBox(width: 2),
                TermInfo(term),
              ],
            ]),
          ),
          Text(v, style: kNum.copyWith(fontSize: 15, color: c ?? AppColors.ink)),
        ],
      ),
    );

// ------------------------------------------------------------------
// K 線全螢幕（橫向）
// ------------------------------------------------------------------
class _KChartFullscreen extends StatefulWidget {
  final List<KLineEntity> entities;
  final List<MainIndicator> main;
  final List<SecondaryIndicator> secondary;
  final String title;
  const _KChartFullscreen({
    required this.entities,
    required this.main,
    required this.secondary,
    required this.title,
  });
  @override
  State<_KChartFullscreen> createState() => _KChartFullscreenState();
}

class _KChartFullscreenState extends State<_KChartFullscreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.ink2),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.ink, fontWeight: FontWeight.w600)),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Text('雙指縮放 · 長按看詳細',
                      style: TextStyle(fontSize: 11, color: AppColors.ink3)),
                ),
              ],
            ),
            Expanded(
              child: KChartWidget(
                widget.entities,
                const KChartStyle(),
                _kchartColors(),
                isTrendLine: false,
                mainIndicators: widget.main,
                secondaryIndicators: widget.secondary,
                fixedLength: 2,
                timeFormat: TimeFormat.YEAR_MONTH_DAY,
                detailBuilder: (e) => Container(
                  padding: const EdgeInsets.all(8),
                  color: AppColors.surface2,
                  child: Text(
                    '開 ${e.open.toStringAsFixed(2)}  高 ${e.high.toStringAsFixed(2)}\n'
                    '低 ${e.low.toStringAsFixed(2)}  收 ${e.close.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// 個股備忘錄分頁
// ------------------------------------------------------------------
class _NotesTab extends ConsumerStatefulWidget {
  final String id;
  const _NotesTab({required this.id});
  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  late final TextEditingController _c =
      TextEditingController(text: ref.read(noteProvider(widget.id)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('個人備忘錄',
                  style: TextStyle(
                      color: AppColors.ink2, fontWeight: FontWeight.w600)),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _c,
                builder: (_, v, child) => Text('${v.text.length}/200',
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.ink3)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _c,
              maxLength: 200,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (t) =>
                  ref.read(notesProvider.notifier).set(widget.id, t),
              style: const TextStyle(color: AppColors.ink, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '記錄買賣理由、目標價、觀察重點…\n只存在這支手機，不會上傳。',
                hintStyle: TextStyle(color: AppColors.ink3, fontSize: 13),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 相關（ETF／比較／期貨）----------------
class _RelatedTab extends StatelessWidget {
  final Symbol symbol;
  final String name;
  const _RelatedTab({required this.symbol, required this.name});

  @override
  Widget build(BuildContext context) {
    final holders = etfsHolding(symbol.code);
    final hasFutures = kHasStockFutures.contains(symbol.code);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _H('個股比較'),
        OutlinedButton.icon(
          icon: const Icon(Icons.show_chart, size: 18),
          label: const Text('跟其他標的比漲跌幅'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ComparePage(base: symbol, baseName: name),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _H('相關 ETF（本檔被以下 ETF 持有）'),
        if (holders.isEmpty)
          const Text('目前收錄的熱門 ETF 中沒有找到',
              style: TextStyle(fontSize: 13, color: AppColors.ink3))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in holders)
                ActionChip(
                  label: Text('${h.etfCode}　權重 ${h.weight.toStringAsFixed(1)}%'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuoteDetailPage(
                        symbol: Symbol(h.etfCode, Market.tse),
                        name: h.etfCode,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 22),
        const _H('相關期貨'),
        Text(
          hasFutures ? '本檔有掛牌股票期貨（台灣期交所）' : '本檔目前查無掛牌的股票期貨',
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        if (hasFutures) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('到期交所查即時行情'),
            onPressed: () => launchUrl(
              Uri.parse(
                  'https://www.taifex.com.tw/cht/3/futDataSearch'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ],
    );
  }
}
