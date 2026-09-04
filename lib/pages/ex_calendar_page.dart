import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market_service.dart';
import '../services/universe_service.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

DateTime? _parseRoc(String s) {
  final m = RegExp(r'(\d+)年(\d+)月(\d+)日').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!) + 1911, int.parse(m[2]!), int.parse(m[3]!));
}

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

class ExCalendarPage extends StatefulWidget {
  final String? filterCode; // 指定時只顯示該檔股票（個股行事曆）
  final String? filterName;
  const ExCalendarPage({super.key, this.filterCode, this.filterName});
  @override
  State<ExCalendarPage> createState() => _ExCalendarPageState();
}

class _ExCalendarPageState extends State<ExCalendarPage> {
  final Map<DateTime, List<ExCalRow>> _byDay = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = _dayKey(DateTime.now());
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await universeService.ensureLoaded();
    var rows = await marketService.exCalendar();
    if (widget.filterCode != null) {
      rows = rows.where((r) => r.code == widget.filterCode).toList();
    }
    _byDay.clear();
    for (final r in rows) {
      final d = _parseRoc(r.date);
      if (d == null) continue;
      _byDay.putIfAbsent(_dayKey(d), () => []).add(r);
    }
    // 有資料的話跳到第一個有事件的月份
    if (_byDay.isNotEmpty) {
      final first = _byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      _month = DateTime(first.year, first.month);
      if (_byDay.containsKey(_selected) == false) {
        _selected = _byDay.keys.contains(_dayKey(DateTime.now()))
            ? _dayKey(DateTime.now())
            : first;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addToCalendar(DateTime day, ExCalRow r) async {
    try {
      final ev = Event(
        title: '${r.kind == '權' ? '除權' : '除息'} ${r.name}(${r.code})'
            '${r.cash > 0 ? ' 現金 ${r.cash.toStringAsFixed(2)} 元' : ''}',
        description: '台股除權息（資料來源：證交所除權除息預告表）',
        location: '',
        startDate: DateTime(day.year, day.month, day.day, 9),
        endDate: DateTime(day.year, day.month, day.day, 10),
        allDay: true,
      );
      await Add2Calendar.addEvent2Cal(ev);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此平台不支援加入行事曆（請在手機上使用）')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _byDay[_selected] ?? const [];
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.filterName != null
              ? '${widget.filterName} 行事曆'
              : '除權息行事曆')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _monthBar(),
                  _grid(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${_selected.year}/${_selected.month}/${_selected.day}'
                      '　${events.isEmpty ? "無除權息" : "${events.length} 檔"}',
                      style: TextStyle(
                          color: AppColors.ink3, fontSize: 13),
                    ),
                  ),
                  if (events.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: Text('這天沒有除權息',
                              style: TextStyle(color: AppColors.ink3))),
                    )
                  else
                    for (final r in events)
                      ListTile(
                        title: Text('${r.name}  ${r.code}'),
                        subtitle: Text(
                          r.kind == '權'
                              ? '除權（配股）'
                              : '除息 · 現金 ${r.cash.toStringAsFixed(2)} 元',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.ink3),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.event_available_outlined),
                          tooltip: '加入行事曆',
                          onPressed: () => _addToCalendar(_selected, r),
                        ),
                        onTap: () {
                          final hit = universeService
                              .search(r.code)
                              .where((x) => x.code == r.code)
                              .toList();
                          final mkt = hit.isNotEmpty
                              ? hit.first.market
                              : Market.tse;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuoteDetailPage(
                                  symbol: Symbol(r.code, mkt),
                                  name: r.name),
                            ),
                          );
                        },
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() =>
                _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Text('${_month.year} 年 ${_month.month} 月',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() =>
                _month = DateTime(_month.year, _month.month + 1)),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // 週日=0
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (final w in ['日', '一', '二', '三', '四', '五', '六']) {
      cells.add(Center(
          child: Text(w,
              style: TextStyle(
                  fontSize: 12, color: AppColors.ink3))));
    }
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = _dayKey(DateTime.now());
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_month.year, _month.month, d);
      final key = _dayKey(day);
      final evs = _byDay[key];
      final sel = key == _selected;
      cells.add(InkWell(
        onTap: () => setState(() => _selected = key),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: sel ? AppColors.accent : null,
            border: !sel && key == today
                ? Border.all(color: AppColors.accent)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$d',
                  style: TextStyle(
                      fontSize: 13,
                      color: sel ? Colors.white : AppColors.ink)),
              const SizedBox(height: 2),
              if (evs != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.white24
                        : AppColors.up.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${evs.length}',
                      style: TextStyle(
                          fontSize: 9,
                          color: sel ? Colors.white : AppColors.up)),
                )
              else
                const SizedBox(height: 11),
            ],
          ),
        ),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.82,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: cells,
    );
  }
}
