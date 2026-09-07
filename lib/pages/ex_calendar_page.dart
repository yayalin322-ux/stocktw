import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/market_service.dart';
import '../services/universe_service.dart';
import '../theme.dart';
import 'quote_detail_page.dart';

DateTime? _parseRoc(String s) {
  final m = RegExp(r'(\d+)年(\d+)月(\d+)日').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!) + 1911, int.parse(m[2]!), int.parse(m[3]!));
}

/// ROC「yyyMMdd」，例 1151013
DateTime? _rocYmd(String s) {
  s = s.trim();
  if (s.length != 7) return null;
  final y = int.tryParse(s.substring(0, 3));
  final m = int.tryParse(s.substring(3, 5));
  final d = int.tryParse(s.substring(5, 7));
  if (y == null || m == null || d == null) return null;
  try {
    return DateTime(y + 1911, m, d);
  } catch (_) {
    return null;
  }
}

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

enum CalType { exRight, exDiv, meeting, report }

class CalEvent {
  final CalType type;
  final String title;
  final String? sub;
  final String? code;
  final String? name;
  CalEvent(this.type, this.title, {this.sub, this.code, this.name});

  String get tag => switch (type) {
        CalType.exRight => '除權',
        CalType.exDiv => '除息',
        CalType.meeting => '股東會',
        CalType.report => '財報',
      };

  Color get color => switch (type) {
        CalType.exRight || CalType.exDiv => AppColors.up,
        CalType.meeting => AppColors.warn,
        CalType.report => AppColors.accent,
      };
}

class ExCalendarPage extends StatefulWidget {
  final String? filterCode; // 指定時只顯示該檔股票（個股行事曆）
  final String? filterName;
  const ExCalendarPage({super.key, this.filterCode, this.filterName});
  @override
  State<ExCalendarPage> createState() => _ExCalendarPageState();
}

class _ExCalendarPageState extends State<ExCalendarPage> {
  final Map<DateTime, List<CalEvent>> _byDay = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = _dayKey(DateTime.now());
  bool _loading = true;
  String _filter = '全部'; // 全部 / 除權息 / 股東會 / 財報

  bool get _perStock => widget.filterCode != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _add(DateTime? d, CalEvent e) {
    if (d == null) return;
    _byDay.putIfAbsent(_dayKey(d), () => []).add(e);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _byDay.clear();
    await universeService.ensureLoaded();

    // 除權息
    try {
      var rows = await marketService.exCalendar();
      if (_perStock) {
        rows = rows.where((r) => r.code == widget.filterCode).toList();
      }
      for (final r in rows) {
        final d = _parseRoc(r.date);
        _add(
          d,
          CalEvent(
            r.kind == '權' ? CalType.exRight : CalType.exDiv,
            '${r.name} ${r.code}',
            sub: r.kind == '權'
                ? '除權（配股）'
                : '除息 · 現金 ${r.cash.toStringAsFixed(2)} 元',
            code: r.code,
            name: r.name,
          ),
        );
      }
    } catch (_) {}

    if (!_perStock) {
      // 股東會（證交所公開資料）
      try {
        final r = await webDio.get<List<dynamic>>(
            'https://openapi.twse.com.tw/v1/opendata/t187ap41_L');
        for (final e in (r.data ?? const [])) {
          if (e is! Map) continue;
          final d = _rocYmd('${e['開會日期'] ?? ''}');
          final code = '${e['公司代號'] ?? ''}';
          final name = '${e['公司名稱'] ?? ''}';
          final kind = '${e['股東常(臨時)會'] ?? '股東會'}';
          final reElect =
              '${e['是否改選董監'] ?? ''}' == '是' ? '．改選董監' : '';
          final place = '${e['開會地點'] ?? ''}';
          _add(
            d,
            CalEvent(CalType.meeting, '$name $code · $kind$reElect',
                sub: place.isEmpty ? null : place, code: code, name: name),
          );
        }
      } catch (_) {}

      // 財報公佈法定期限（規則；一般公司）
      final yr = DateTime.now().year;
      for (final y in [yr, yr + 1]) {
        _add(DateTime(y, 3, 31),
            CalEvent(CalType.report, '$y 年報公佈期限', sub: '前一年度全年財報'));
        _add(DateTime(y, 5, 15),
            CalEvent(CalType.report, '$y 第一季財報公佈期限', sub: 'Q1'));
        _add(DateTime(y, 8, 14),
            CalEvent(CalType.report, '$y 半年報公佈期限', sub: 'Q2 累計'));
        _add(DateTime(y, 11, 14),
            CalEvent(CalType.report, '$y 第三季財報公佈期限', sub: 'Q3'));
      }
    }

    if (_byDay.isNotEmpty) {
      final today = _dayKey(DateTime.now());
      if (_byDay.containsKey(today)) {
        _month = DateTime(today.year, today.month);
        _selected = today;
      } else {
        final upcoming = _byDay.keys.where((k) => !k.isBefore(today)).toList()
          ..sort();
        final pick = upcoming.isNotEmpty
            ? upcoming.first
            : _byDay.keys.reduce((a, b) => a.isAfter(b) ? a : b);
        _month = DateTime(pick.year, pick.month);
        _selected = pick;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _passFilter(CalEvent e) {
    if (_filter == '全部') return true;
    if (_filter == '除權息') {
      return e.type == CalType.exRight || e.type == CalType.exDiv;
    }
    if (_filter == '股東會') return e.type == CalType.meeting;
    if (_filter == '財報') return e.type == CalType.report;
    return true;
  }

  Future<void> _addToCalendar(DateTime day, CalEvent e) async {
    try {
      final ev = Event(
        title: '[${e.tag}] ${e.title}',
        description: e.sub ?? '股市 Pro 重大行事曆',
        location: (e.type == CalType.meeting ? e.sub : '') ?? '',
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
    final events =
        (_byDay[_selected] ?? const <CalEvent>[]).where(_passFilter).toList();
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.filterName != null
              ? '${widget.filterName} 行事曆'
              : '重大行事曆')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (!_perStock)
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: ['全部', '除權息', '股東會', '財報'].map((f) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 7),
                            child: ChoiceChip(
                              label: Text(f),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  _monthBar(),
                  _grid(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${_selected.year}/${_selected.month}/${_selected.day}'
                      '　${events.isEmpty ? "無事件" : "${events.length} 項"}',
                      style: TextStyle(color: AppColors.ink3, fontSize: 13),
                    ),
                  ),
                  if (events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('這天沒有行程')),
                    )
                  else
                    for (final e in events) _eventTile(e),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _eventTile(CalEvent e) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: e.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(e.tag,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: e.color)),
      ),
      title: Text(e.title, style: const TextStyle(fontSize: 14)),
      subtitle: e.sub == null
          ? null
          : Text(e.sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.ink3)),
      trailing: IconButton(
        icon: const Icon(Icons.event_available_outlined),
        tooltip: '加入手機行事曆',
        onPressed: () => _addToCalendar(_selected, e),
      ),
      onTap: e.code == null
          ? null
          : () {
              final hit = universeService
                  .search(e.code!)
                  .where((x) => x.code == e.code)
                  .toList();
              final mkt = hit.isNotEmpty ? hit.first.market : Market.tse;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuoteDetailPage(
                      symbol: Symbol(e.code!, mkt), name: e.name ?? e.code!),
                ),
              );
            },
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Text('${_month.year} 年 ${_month.month} 月',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final firstWeekday =
        DateTime(_month.year, _month.month, 1).weekday % 7; // 週日=0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (final w in ['日', '一', '二', '三', '四', '五', '六']) {
      cells.add(Center(
          child: Text(w,
              style: TextStyle(fontSize: 12, color: AppColors.ink3))));
    }
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = _dayKey(DateTime.now());
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(_month.year, _month.month, d);
      final key = _dayKey(day);
      final evs =
          (_byDay[key] ?? const <CalEvent>[]).where(_passFilter).toList();
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
              if (evs.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in _dotColors(evs))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : c,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                )
              else
                const SizedBox(height: 5),
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

  List<Color> _dotColors(List<CalEvent> evs) {
    final seen = <Color>{};
    for (final e in evs) {
      seen.add(e.color);
      if (seen.length >= 3) break;
    }
    return seen.toList();
  }
}
