import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase/push.dart';
import 'models.dart';
import 'services/candle_service.dart';
import 'services/notifications.dart';
import 'services/quote_service.dart';
import 'services/widget_service.dart';
import 'theme.dart';

/// 於 main() override
final prefsProvider = Provider<SharedPreferences>((_) {
  throw UnimplementedError('prefsProvider 必須在 main 覆寫');
});

/// 底部分頁索引（讓主頁卡片可跳到其他分頁）
final tabIndexProvider = StateProvider<int>((_) => 0);

// ------------------------------------------------------------------
// 自選股
// ------------------------------------------------------------------
/// 自選股支援多群組。`state` = 目前選中群組的清單（畫面顯示用）。
class WatchlistNotifier extends StateNotifier<List<Symbol>> {
  WatchlistNotifier(this._prefs) : super(const []) {
    _loadAll();
  }
  final SharedPreferences _prefs;
  static const _keyV2 = 'watchlist.groups.v1';
  static const _keyV1 = 'watchlist'; // 舊版單一清單

  final Map<String, List<Symbol>> _groups = {};
  List<String> _order = [];
  String _current = '自選';

  static const _seed = [
    Symbol('2330', Market.tse),
    Symbol('2317', Market.tse),
    Symbol('2454', Market.tse),
    Symbol('0050', Market.tse),
    Symbol('2412', Market.tse),
  ];

  void _loadAll() {
    final raw = _prefs.getString(_keyV2);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _order = (m['order'] as List).cast<String>();
        final g = m['groups'] as Map<String, dynamic>;
        for (final name in _order) {
          _groups[name] = ((g[name] as List?) ?? const [])
              .map((e) => Symbol.parse(e as String))
              .toList();
        }
        _current = m['current'] as String? ?? '';
      } catch (_) {
        _groups.clear();
        _order = [];
      }
    } else {
      final old = _prefs.getStringList(_keyV1);
      if (old != null && old.isNotEmpty) {
        _groups['自選'] = old.map(Symbol.parse).toList();
        _order = ['自選'];
      }
    }
    if (_groups.isEmpty) {
      _groups['自選'] = [..._seed];
      _order = ['自選'];
    }
    if (!_groups.containsKey(_current)) _current = _order.first;
    state = [..._groups[_current]!];
    _save();
  }

  void _save() {
    _prefs.setString(
      _keyV2,
      jsonEncode({
        'order': _order,
        'current': _current,
        'groups': {
          for (final e in _groups.entries)
            e.key: e.value.map((s) => s.id).toList(),
        },
      }),
    );
  }

  // ---------- 群組 ----------
  List<String> get groupNames => List.unmodifiable(_order);
  String get currentGroup => _current;
  int countOf(String name) => _groups[name]?.length ?? 0;

  /// 全部群組的標的聯集（輪詢報價、判斷是否已加入用）
  List<Symbol> get allSymbols =>
      <Symbol>{for (final l in _groups.values) ...l}.toList();

  bool containsAnywhere(Symbol s) =>
      _groups.values.any((l) => l.contains(s));

  String? groupOf(Symbol s) {
    for (final e in _groups.entries) {
      if (e.value.contains(s)) return e.key;
    }
    return null;
  }

  void switchGroup(String name) {
    if (!_groups.containsKey(name) || name == _current) return;
    _current = name;
    state = [..._groups[name]!];
    _save();
  }

  void addGroup(String name) {
    final n = name.trim();
    if (n.isEmpty || _groups.containsKey(n)) return;
    _groups[n] = [];
    _order = [..._order, n];
    _current = n;
    state = const [];
    _save();
  }

  void renameGroup(String from, String to) {
    final t = to.trim();
    if (t.isEmpty ||
        from == t ||
        !_groups.containsKey(from) ||
        _groups.containsKey(t)) {
      return;
    }
    _groups[t] = _groups.remove(from)!;
    _order = [for (final o in _order) o == from ? t : o];
    if (_current == from) {
      _current = t;
    }
    state = [..._groups[_current]!];
    _save();
  }

  void removeGroup(String name) {
    if (_groups.length <= 1 || !_groups.containsKey(name)) return;
    _groups.remove(name);
    _order = _order.where((o) => o != name).toList();
    if (_current == name) _current = _order.first;
    state = [..._groups[_current]!];
    _save();
  }

  // ---------- 個股（作用在目前群組）----------
  void add(Symbol s) {
    final cur = _groups[_current]!;
    if (cur.contains(s)) return;
    _groups[_current] = [...cur, s];
    state = [..._groups[_current]!];
    _save();
  }

  /// 從所有群組移除（星號切換直覺）
  void remove(Symbol s) {
    var changed = false;
    for (final k in _groups.keys.toList()) {
      if (_groups[k]!.contains(s)) {
        _groups[k] = _groups[k]!.where((e) => e != s).toList();
        changed = true;
      }
    }
    if (changed) {
      state = [..._groups[_current]!];
      _save();
    }
  }

  void moveToGroup(Symbol s, String target) {
    if (!_groups.containsKey(target)) return;
    for (final k in _groups.keys.toList()) {
      _groups[k] = _groups[k]!.where((e) => e != s).toList();
    }
    _groups[target] = [..._groups[target]!, s];
    state = [..._groups[_current]!];
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [..._groups[_current]!];
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    _groups[_current] = list;
    state = [...list];
    _save();
  }

  // ---------- QR 匯出／匯入 ----------
  int get totalCount => _groups.values.fold(0, (a, l) => a + l.length);

  /// 給 QR 匯出用的資料（純 Map，外層由匯出頁決定怎麼包）
  Map<String, dynamic> exportMap() => {
        'g': [
          for (final name in _order)
            {'n': name, 's': _groups[name]!.map((s) => s.id).toList()},
        ],
      };

  /// 掃描別台手機的 QR 後合併進來（同名群組合併，不覆蓋既有資料）。
  /// 回傳 (新增群組數, 新增股票數)。
  (int, int) importMerge(Map<String, dynamic> wlMap) {
    final gList = wlMap['g'];
    if (gList is! List) return (0, 0);
    var newGroups = 0, newStocks = 0;
    for (final g in gList) {
      if (g is! Map || g['n'] is! String || g['s'] is! List) continue;
      final name = g['n'] as String;
      final syms = (g['s'] as List).whereType<String>().map(Symbol.parse);
      if (!_groups.containsKey(name)) {
        _groups[name] = [];
        _order = [..._order, name];
        newGroups++;
      }
      for (final s in syms) {
        if (!_groups[name]!.contains(s)) {
          _groups[name] = [..._groups[name]!, s];
          newStocks++;
        }
      }
    }
    state = [...(_groups[_current] ?? const [])];
    _save();
    return (newGroups, newStocks);
  }
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, List<Symbol>>((ref) {
  return WatchlistNotifier(ref.watch(prefsProvider));
});

// ------------------------------------------------------------------
// 持倉
// ------------------------------------------------------------------
class PortfolioNotifier extends StateNotifier<List<Position>> {
  PortfolioNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'portfolio';

  static List<Position> _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => Position.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _save() =>
      _prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));

  void upsert(Position p) {
    final i = state.indexWhere((e) => e.id == p.id);
    state = i >= 0
        ? [for (final e in state) e.id == p.id ? p : e]
        : [...state, p];
    _save();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  /// 給 QR 匯出用的資料
  List<Map<String, dynamic>> exportMap() =>
      state.map((e) => e.toJson()).toList();

  /// QR 匯入：只新增本來沒有的標的，已存在的成本/股數不覆蓋。
  /// 回傳新增了幾檔。
  int importMerge(List<Position> incoming) {
    var added = 0;
    var next = state;
    for (final p in incoming) {
      if (next.any((e) => e.id == p.id)) continue;
      next = [...next, p];
      added++;
    }
    if (added > 0) {
      state = next;
      _save();
    }
    return added;
  }
}

final portfolioProvider =
    StateNotifierProvider<PortfolioNotifier, List<Position>>((ref) {
  return PortfolioNotifier(ref.watch(prefsProvider));
});

// ------------------------------------------------------------------
// 到價提醒
// ------------------------------------------------------------------
class AlertsNotifier extends StateNotifier<List<PriceAlert>> {
  AlertsNotifier(this._prefs) : super(_load(_prefs)) {
    // 技術面提醒要抓日K算均線，比對價格重很多，5 分鐘查一次就夠
    _maTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkMaCross());
    _checkMaCross();
  }
  final SharedPreferences _prefs;
  static const _key = 'alerts';
  Timer? _maTimer;

  static List<PriceAlert> _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => PriceAlert.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void save() {
    _prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
    syncAlerts(state); // 同步到雲端（未啟用 Firebase 時 no-op）
  }

  void add(PriceAlert a) {
    state = [...state, a];
    save();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    save();
  }

  void update(List<PriceAlert> next) {
    state = next;
    save();
  }

  /// App 開著時，定期抓日K檢查技術面提醒（站上/跌破均線）。
  /// App 關閉時的檢查由 GitHub Actions 的 check-alerts 腳本負責。
  Future<void> _checkMaCross() async {
    final targets = state.where((a) => !a.triggered && a.kind == 'ma_cross').toList();
    if (targets.isEmpty) return;
    var changed = false;
    for (final a in targets) {
      final period = a.maPeriod ?? 20;
      try {
        final candles = await candleService.fetch(Symbol(a.code, a.market),
            range: '3mo', interval: '1d');
        if (candles.length < period + 2) continue;
        final closes = candles.map((c) => c.close).toList();
        final n = closes.length;
        double sma(int idx) {
          var sum = 0.0;
          for (var i = idx - period + 1; i <= idx; i++) {
            sum += closes[i];
          }
          return sum / period;
        }

        final maPrev = sma(n - 2), maNow = sma(n - 1);
        final prevClose = closes[n - 2], nowClose = closes[n - 1];
        final crossUp = a.crossUp ?? true;
        final hit = crossUp
            ? (prevClose < maPrev && nowClose >= maNow)
            : (prevClose > maPrev && nowClose <= maNow);
        if (hit) {
          a.triggered = true;
          changed = true;
          notify(
            '${a.name} ${a.code} 技術面提醒',
            '${crossUp ? "站上" : "跌破"} MA$period（現價 ${nowClose.toStringAsFixed(2)}）',
          );
        }
      } catch (_) {
        // 靜默：下一輪再試
      }
    }
    if (changed) save();
  }

  @override
  void dispose() {
    _maTimer?.cancel();
    super.dispose();
  }
}

final alertsProvider =
    StateNotifierProvider<AlertsNotifier, List<PriceAlert>>((ref) {
  return AlertsNotifier(ref.watch(prefsProvider));
});

// ------------------------------------------------------------------
// 即時報價（輪詢 = 自選 ∪ 持倉 ∪ 提醒 的聯集）
// ------------------------------------------------------------------
class QuotesNotifier extends StateNotifier<Map<String, Quote>> {
  QuotesNotifier(this.ref) : super({}) {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    refresh();
  }
  final Ref ref;
  Timer? _timer;
  bool _busy = false;
  DateTime? _lastWidgetUpdate;

  /// 暫時訂閱（個股頁開著時），計數式
  final Map<String, int> _extra = {};

  void subscribe(Symbol s) {
    _extra[s.id] = (_extra[s.id] ?? 0) + 1;
    refresh();
  }

  void unsubscribe(Symbol s) {
    final n = (_extra[s.id] ?? 0) - 1;
    if (n <= 0) {
      _extra.remove(s.id);
    } else {
      _extra[s.id] = n;
    }
  }

  Set<Symbol> get _symbols {
    final s = <Symbol>{...ref.read(watchlistProvider.notifier).allSymbols};
    for (final p in ref.read(portfolioProvider)) {
      s.add(Symbol(p.code, p.market));
    }
    for (final a in ref.read(alertsProvider)) {
      s.add(Symbol(a.code, a.market));
    }
    for (final id in _extra.keys) {
      s.add(Symbol.parse(id));
    }
    return s;
  }

  Future<void> refresh() async {
    if (_busy) return;
    final syms = _symbols.toList();
    if (syms.isEmpty) return;
    _busy = true;
    try {
      final fresh = await quoteService.fetch(syms);
      if (fresh.isNotEmpty) {
        state = {...state, ...fresh};
        _checkAlerts();
        // 桌面小工具不用跟著 5 秒報價一起洗，1 分鐘更新一次就夠
        final now = DateTime.now();
        if (_lastWidgetUpdate == null ||
            now.difference(_lastWidgetUpdate!) > const Duration(minutes: 1)) {
          _lastWidgetUpdate = now;
          updateHomeWidget(ref.read(watchlistProvider), state);
        }
      }
    } catch (_) {
      // 靜默：下一輪再試
    } finally {
      _busy = false;
    }
  }

  void _checkAlerts() {
    final alerts = ref.read(alertsProvider);
    var changed = false;
    final next = <PriceAlert>[];
    for (final a in alerts) {
      final px = state[Symbol(a.code, a.market).id]?.price;
      if (a.kind == 'price' && !a.triggered && px != null) {
        final hit = a.above ? px >= a.target : px <= a.target;
        if (hit) {
          a.triggered = true;
          changed = true;
          notify(
            '${a.name} ${a.code} 到價',
            '${a.above ? '漲抵' : '跌抵'} ${a.target.toStringAsFixed(2)}（現價 ${px.toStringAsFixed(2)}）',
          );
        }
      }
      next.add(a);
    }
    if (changed) ref.read(alertsProvider.notifier).update(next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final quotesProvider =
    StateNotifierProvider<QuotesNotifier, Map<String, Quote>>((ref) {
  // 讓輪詢集合隨這些清單變動而更新
  ref.watch(watchlistProvider);
  ref.watch(portfolioProvider);
  ref.watch(alertsProvider);
  return QuotesNotifier(ref);
});

/// 單一標的報價
final quoteProvider = Provider.family<Quote?, Symbol>((ref, s) {
  return ref.watch(quotesProvider)[s.id];
});

// ------------------------------------------------------------------
// 最近看過（搜尋頁用）
// ------------------------------------------------------------------
class RecentNotifier extends StateNotifier<List<(Symbol, String)>> {
  RecentNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'recent.v1';

  static List<(Symbol, String)> _load(SharedPreferences p) {
    return (p.getStringList(_key) ?? [])
        .map((e) {
          final i = e.indexOf('|');
          return i < 0
              ? (Symbol.parse(e), e)
              : (Symbol.parse(e.substring(0, i)), e.substring(i + 1));
        })
        .toList();
  }

  void add(Symbol s, String name) {
    final next = [
      (s, name),
      ...state.where((e) => e.$1 != s),
    ].take(12).toList();
    state = next;
    _prefs.setStringList(_key, next.map((e) => '${e.$1.id}|${e.$2}').toList());
  }
}

final recentProvider =
    StateNotifierProvider<RecentNotifier, List<(Symbol, String)>>((ref) {
  return RecentNotifier(ref.watch(prefsProvider));
});

// ------------------------------------------------------------------
// 個股備忘錄（每檔一段筆記，只存本機）
// ------------------------------------------------------------------
class NotesNotifier extends StateNotifier<Map<String, String>> {
  NotesNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'notes.v1';

  static Map<String, String> _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  void set(String id, String text) {
    final t = text.trim();
    final next = {...state};
    if (t.isEmpty) {
      next.remove(id);
    } else {
      next[id] = t;
    }
    state = next;
    _prefs.setString(_key, jsonEncode(state));
  }
}

final notesProvider =
    StateNotifierProvider<NotesNotifier, Map<String, String>>((ref) {
  return NotesNotifier(ref.watch(prefsProvider));
});

/// 單一標的備忘錄文字（空字串表示尚未填）
final noteProvider = Provider.family<String, String>((ref, id) {
  return ref.watch(notesProvider)[id] ?? '';
});

// ------------------------------------------------------------------
// 持倉金額隱私開關（持倉頁「眼睛」鈕，記住上次的選擇）
// ------------------------------------------------------------------
class HideAmountsNotifier extends StateNotifier<bool> {
  HideAmountsNotifier(this._prefs)
      : super(_prefs.getBool(_key) ?? false);
  final SharedPreferences _prefs;
  static const _key = 'hideAmounts';

  void toggle() {
    state = !state;
    _prefs.setBool(_key, state);
  }
}

final hideAmountsProvider =
    StateNotifierProvider<HideAmountsNotifier, bool>((ref) {
  return HideAmountsNotifier(ref.watch(prefsProvider));
});

/// 依隱私開關決定要顯示原字串還是遮住
String maskable(bool hide, String text) => hide ? '••••••' : text;

// ------------------------------------------------------------------
// 淺色／深色主題（記住上次選擇）
// ------------------------------------------------------------------
class ThemeModeNotifier extends StateNotifier<bool> {
  ThemeModeNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false) {
    AppColors.setLight(state);
  }
  final SharedPreferences _prefs;
  static const _key = 'themeLight';

  void toggle() {
    state = !state;
    AppColors.setLight(state);
    _prefs.setBool(_key, state);
  }
}

/// true = 淺色
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, bool>((ref) {
  return ThemeModeNotifier(ref.watch(prefsProvider));
});
