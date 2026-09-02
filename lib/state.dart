import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase/push.dart';
import 'models.dart';
import 'services/notifications.dart';
import 'services/quote_service.dart';

/// 於 main() override
final prefsProvider = Provider<SharedPreferences>((_) {
  throw UnimplementedError('prefsProvider 必須在 main 覆寫');
});

/// 底部分頁索引（讓主頁卡片可跳到其他分頁）
final tabIndexProvider = StateProvider<int>((_) => 0);

// ------------------------------------------------------------------
// 自選股
// ------------------------------------------------------------------
class WatchlistNotifier extends StateNotifier<List<Symbol>> {
  WatchlistNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'watchlist';

  static List<Symbol> _load(SharedPreferences p) {
    final raw = p.getStringList(_key);
    if (raw == null || raw.isEmpty) {
      return const [
        Symbol('2330', Market.tse),
        Symbol('2317', Market.tse),
        Symbol('2454', Market.tse),
        Symbol('0050', Market.tse),
        Symbol('2412', Market.tse),
      ];
    }
    return raw.map(Symbol.parse).toList();
  }

  void _save() => _prefs.setStringList(_key, state.map((s) => s.id).toList());

  void add(Symbol s) {
    if (state.contains(s)) return;
    state = [...state, s];
    _save();
  }

  void remove(Symbol s) {
    state = state.where((e) => e != s).toList();
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    state = list;
    _save();
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
}

final portfolioProvider =
    StateNotifierProvider<PortfolioNotifier, List<Position>>((ref) {
  return PortfolioNotifier(ref.watch(prefsProvider));
});

// ------------------------------------------------------------------
// 到價提醒
// ------------------------------------------------------------------
class AlertsNotifier extends StateNotifier<List<PriceAlert>> {
  AlertsNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'alerts';

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
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
    refresh();
  }
  final Ref ref;
  Timer? _timer;
  bool _busy = false;

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
    final s = <Symbol>{...ref.read(watchlistProvider)};
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
      if (!a.triggered && px != null) {
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
