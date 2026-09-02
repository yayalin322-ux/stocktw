import 'package:flutter/material.dart';
import 'theme.dart';

enum MarketSession { preOpen, open, afterHours, closed }

class SessionInfo {
  final MarketSession session;
  final String label;
  final Color color;
  final String clock; // HH:mm（台北）
  const SessionInfo(this.session, this.label, this.color, this.clock);
}

/// 依台北時間判斷台股目前時段（不含假日行事曆）
SessionInfo currentSession([DateTime? nowUtc]) {
  final tpe = (nowUtc ?? DateTime.now().toUtc())
      .add(const Duration(hours: 8)); // Asia/Taipei，無 DST
  final hm = tpe.hour * 60 + tpe.minute;
  final clock =
      '${tpe.hour.toString().padLeft(2, '0')}:${tpe.minute.toString().padLeft(2, '0')}';
  final weekend = tpe.weekday == DateTime.saturday || tpe.weekday == DateTime.sunday;

  if (weekend) {
    return SessionInfo(MarketSession.closed, '休市', AppColors.ink3, clock);
  }
  if (hm >= 8 * 60 + 30 && hm < 9 * 60) {
    return SessionInfo(MarketSession.preOpen, '盤前試撮', AppColors.warn, clock);
  }
  if (hm >= 9 * 60 && hm < 13 * 60 + 30) {
    return SessionInfo(MarketSession.open, '盤中', AppColors.up, clock);
  }
  if (hm >= 13 * 60 + 30 && hm < 14 * 60 + 30) {
    return SessionInfo(MarketSession.afterHours, '盤後', AppColors.accent, clock);
  }
  return SessionInfo(MarketSession.closed, '已收盤', AppColors.ink3, clock);
}

/// 時段小膠囊（每 30 秒自動更新）
class SessionPill extends StatefulWidget {
  const SessionPill({super.key});
  @override
  State<SessionPill> createState() => _SessionPillState();
}

class _SessionPillState extends State<SessionPill> {
  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() {});
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = currentSession();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('${s.label} · ${s.clock}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: s.color)),
      ]),
    );
  }
}
