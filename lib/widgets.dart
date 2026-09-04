import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';
import 'theme.dart';

/// 迷你走勢線
class Sparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double baseline; // 前收，決定漲跌著色；null 時用首值
  const Sparkline(this.data,
      {super.key, this.color = AppColors.accent, this.baseline = double.nan});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparkPainter(data, color, baseline), size: Size.infinite);
}

class _SparkPainter extends CustomPainter {
  final List<double> d;
  final Color color;
  final double base;
  _SparkPainter(this.d, this.color, this.base);
  @override
  void paint(Canvas c, Size s) {
    if (d.length < 2) return;
    final lo = d.reduce((a, b) => a < b ? a : b);
    final hi = d.reduce((a, b) => a > b ? a : b);
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    double x(int i) => i / (d.length - 1) * s.width;
    double y(double v) => s.height - (v - lo) / range * s.height;
    final path = ui.Path()..moveTo(0, y(d.first));
    for (var i = 1; i < d.length; i++) {
      path.lineTo(x(i), y(d[i]));
    }
    final b = base.isNaN ? d.first : base;
    final col = d.last >= b ? AppColors.up : AppColors.down;
    final fill = ui.Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, s.height), [
            col.withValues(alpha: 0.25),
            col.withValues(alpha: 0.0),
          ]));
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = col);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.d != d;
}

/// 漲跌著色數字
class ChangeText extends StatelessWidget {
  final num? change;
  final num? pct;
  final double size;
  final bool showPct;
  const ChangeText(this.change, this.pct,
      {super.key, this.size = 14, this.showPct = true});

  @override
  Widget build(BuildContext context) {
    if (change == null) {
      return Text('--', style: TextStyle(fontSize: size, color: AppColors.ink3));
    }
    final c = AppColors.forChange(change!);
    final arrow = change! > 0 ? '▲' : (change! < 0 ? '▼' : '');
    return Text(
      showPct
          ? '$arrow ${signed(change!)}  ${signed(pct ?? 0, 2)}%'
          : '$arrow ${signed(change!)}',
      style: kNum.copyWith(fontSize: size, color: c),
    );
  }
}

/// 大字現價
class PriceText extends StatelessWidget {
  final double? price;
  final num? change;
  final double size;
  const PriceText(this.price, this.change, {super.key, this.size = 30});
  @override
  Widget build(BuildContext context) {
    return Text(
      price == null ? '--' : price!.toStringAsFixed(2),
      style: kNum.copyWith(
        fontSize: size,
        color: change == null ? AppColors.ink : AppColors.forChange(change!),
      ),
    );
  }
}

/// 個股/指數分時走勢圖（價格線 + 昨收基準 + 量；可標盤前盤後）
class IntradayChart extends StatelessWidget {
  final List<double> prices;
  final List<double> volumes;
  final double prevClose;
  final List<int> times; // epoch 秒；提供時用時間定位 x 軸
  final int? regStart; // 正常盤 epoch 秒
  final int? regEnd;
  final Map<String, double> cdp; // CDP 壓力/支撐點位（標籤 -> 價）
  const IntradayChart(
    this.prices,
    this.volumes,
    this.prevClose, {
    super.key,
    this.times = const [],
    this.regStart,
    this.regEnd,
    this.cdp = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (prices.length < 2) {
      return const Center(
          child: Text('無分時資料（非交易時段）',
              style: TextStyle(color: AppColors.ink3)));
    }
    final span = [prevClose, ...prices, ...cdp.values];
    final lo = span.reduce((a, b) => a < b ? a : b);
    final hi = span.reduce((a, b) => a > b ? a : b);
    final up = prices.last >= prevClose;
    final col = up ? AppColors.up : AppColors.down;

    final useTime = times.length == prices.length && times.length > 1;
    final t0 = useTime ? times.first : 0;
    final tN = useTime ? times.last : prices.length - 1;
    double frac(int t) => (tN - t0) == 0 ? 0 : (t - t0) / (tN - t0);
    final preFrac = (useTime && regStart != null && regStart! > t0)
        ? frac(regStart!).clamp(0.0, 1.0)
        : 0.0;
    final postFrac = (useTime && regEnd != null && regEnd! < tN)
        ? frac(regEnd!).clamp(0.0, 1.0)
        : 1.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('高 ${hi.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.up)),
              Text('昨收 ${prevClose.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
              Text('低 ${lo.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.down)),
            ],
          ),
        ),
        if (preFrac > 0 || postFrac < 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Row(children: [
              if (preFrac > 0) _tagPP('盤前'),
              const Spacer(),
              if (postFrac < 1) _tagPP('盤後'),
            ]),
          ),
        Expanded(
          child: CustomPaint(
            painter: _IntradayPainter(
                prices, prevClose, lo, hi, col, preFrac, postFrac, cdp),
            size: Size.infinite,
          ),
        ),
        if (cdp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final e in cdp.entries)
                  Text(
                    '${e.key} ${e.value.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: e.key.startsWith('壓')
                          ? AppColors.up
                          : e.key.startsWith('支')
                              ? AppColors.down
                              : AppColors.ink3,
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 44,
          child: CustomPaint(
            painter: _VolPainter(volumes, prices, prevClose),
            size: Size.infinite,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(useTime ? _hm(times.first) : '',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.ink3)),
              Text(useTime ? _hm(times.last) : '',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.ink3)),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _tagPP(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: AppColors.ink3.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4)),
        child: Text(t,
            style: const TextStyle(fontSize: 9, color: AppColors.ink3)),
      );

  static String _hm(int sec) {
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _IntradayPainter extends CustomPainter {
  final List<double> p;
  final double prev, lo, hi;
  final Color col;
  final double preFrac, postFrac;
  final Map<String, double> cdp;
  _IntradayPainter(this.p, this.prev, this.lo, this.hi, this.col, this.preFrac,
      this.postFrac, this.cdp);
  @override
  void paint(Canvas c, Size s) {
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final n = p.length - 1;
    double x(int i) => n == 0 ? 0 : i / n * s.width;
    double y(double v) => s.height - (v - lo) / range * s.height;

    // CDP 壓力/支撐水平線
    for (final e in cdp.entries) {
      final yy = y(e.value);
      if (yy.isNaN || yy < 0 || yy > s.height) continue;
      final isRef = !e.key.startsWith('壓') && !e.key.startsWith('支');
      final lc = (e.key.startsWith('壓')
              ? AppColors.up
              : e.key.startsWith('支')
                  ? AppColors.down
                  : AppColors.ink3)
          .withValues(alpha: isRef ? 0.5 : 0.35);
      final lp = Paint()
        ..color = lc
        ..strokeWidth = 1;
      for (double dx = 0; dx < s.width; dx += 7) {
        c.drawLine(Offset(dx, yy), Offset(dx + 3.5, yy), lp);
      }
    }

    // 盤前/盤後底色
    final wash = Paint()..color = AppColors.ink3.withValues(alpha: 0.08);
    if (preFrac > 0) {
      c.drawRect(Rect.fromLTWH(0, 0, preFrac * s.width, s.height), wash);
      c.drawLine(Offset(preFrac * s.width, 0),
          Offset(preFrac * s.width, s.height),
          Paint()..color = AppColors.border);
    }
    if (postFrac < 1) {
      c.drawRect(
          Rect.fromLTWH(postFrac * s.width, 0, (1 - postFrac) * s.width,
              s.height),
          wash);
      c.drawLine(Offset(postFrac * s.width, 0),
          Offset(postFrac * s.width, s.height),
          Paint()..color = AppColors.border);
    }

    // 昨收虛線
    final yp = y(prev);
    final dash = Paint()
      ..color = AppColors.ink3
      ..strokeWidth = 1;
    for (double dx = 0; dx < s.width; dx += 6) {
      c.drawLine(Offset(dx, yp), Offset(dx + 3, yp), dash);
    }

    final path = ui.Path()..moveTo(0, y(p.first));
    for (var i = 1; i < p.length; i++) {
      path.lineTo(x(i), y(p[i]));
    }
    final fill = ui.Path.from(path)
      ..lineTo(x(n), s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, s.height), [
            col.withValues(alpha: 0.22),
            col.withValues(alpha: 0.0),
          ]));
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = col);
  }

  @override
  bool shouldRepaint(_IntradayPainter o) =>
      o.p != p ||
      o.preFrac != preFrac ||
      o.postFrac != postFrac ||
      o.cdp != cdp;
}

class _VolPainter extends CustomPainter {
  final List<double> v;
  final List<double> p;
  final double prev;
  _VolPainter(this.v, this.p, this.prev);
  @override
  void paint(Canvas c, Size s) {
    if (v.isEmpty) return;
    final mx = v.reduce((a, b) => a > b ? a : b);
    if (mx <= 0) return;
    final n = v.length - 1;
    final bw = n == 0 ? s.width : s.width / v.length;
    for (var i = 0; i < v.length; i++) {
      final h = v[i] / mx * s.height;
      final rising = i == 0 || p[i] >= (i > 0 ? p[i - 1] : prev);
      c.drawRect(
        Rect.fromLTWH((n == 0 ? 0 : i / n * s.width), s.height - h,
            bw * 0.7, h),
        Paint()
          ..color = (rising ? AppColors.up : AppColors.down)
              .withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_VolPainter o) => o.v != v;
}

/// 中線發散的水平長條（正右負左），給三大法人買賣超之類用
class DivergingBar extends StatelessWidget {
  final double value;
  final double maxAbs;
  final double height;
  const DivergingBar(this.value, this.maxAbs,
      {super.key, this.height = 16});
  @override
  Widget build(BuildContext context) {
    final frac = maxAbs <= 0 ? 0.0 : (value.abs() / maxAbs).clamp(0.0, 1.0);
    final c = AppColors.forChange(value);
    return LayoutBuilder(builder: (_, cns) {
      final half = cns.maxWidth / 2;
      return SizedBox(
        height: height,
        child: Stack(children: [
          Positioned(
            left: half,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: AppColors.border),
          ),
          Positioned(
            left: value >= 0 ? half : half - frac * half,
            width: frac * half,
            top: 2,
            bottom: 2,
            child: Container(
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// 由左往右的比例長條（權重、成交值排行等）
class RatioBar extends StatelessWidget {
  final double frac; // 0~1
  final Color color;
  final double height;
  const RatioBar(this.frac,
      {super.key, this.color = AppColors.accent, this.height = 14});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: frac.clamp(0.02, 1.0),
            child: Container(
                height: height, color: color.withValues(alpha: 0.5)),
          ),
        ),
      );
}

/// 一般歷史折線圖（指數/標的皆可）
class PriceLineChart extends StatelessWidget {
  final List<double> data;
  final List<String> xLabels; // 底部時間標籤（左中右三個）
  const PriceLineChart(this.data, {super.key, this.xLabels = const []});
  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return const Center(
          child: Text('無資料', style: TextStyle(color: AppColors.ink3)));
    }
    final lo = data.reduce((a, b) => a < b ? a : b);
    final hi = data.reduce((a, b) => a > b ? a : b);
    final up = data.last >= data.first;
    final col = up ? AppColors.up : AppColors.down;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('高 ${hi.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.up)),
              Text('低 ${lo.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.down)),
            ],
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: _LinePainter(data, lo, hi, col),
            size: Size.infinite,
          ),
        ),
        if (xLabels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in xLabels)
                  Text(t,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.ink3)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> d;
  final double lo, hi;
  final Color col;
  _LinePainter(this.d, this.lo, this.hi, this.col);
  @override
  void paint(Canvas c, Size s) {
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    double x(int i) => i / (d.length - 1) * s.width;
    double y(double v) => s.height - (v - lo) / range * s.height;
    final path = ui.Path()..moveTo(0, y(d.first));
    for (var i = 1; i < d.length; i++) {
      path.lineTo(x(i), y(d[i]));
    }
    final fill = ui.Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, s.height), [
            col.withValues(alpha: 0.22),
            col.withValues(alpha: 0.0),
          ]));
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = col);
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.d != d;
}

/// 自選 / 持倉的一列
class QuoteRow extends StatelessWidget {
  final String code;
  final String name;
  final Quote? q;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  const QuoteRow({
    super.key,
    required this.code,
    required this.name,
    required this.q,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final chgColor =
        q?.change == null ? AppColors.surface2 : AppColors.forChange(q!.change!);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(width: 3, height: 38, color: chgColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? code : name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(code,
                      style: const TextStyle(
                          color: AppColors.ink3, fontSize: 12)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PriceText(q?.price, q?.change, size: 17),
                  const SizedBox(height: 3),
                  ChangeText(q?.change, q?.changePct, size: 12),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatTile(this.label, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: kNum.copyWith(
                fontSize: 18, color: color ?? AppColors.ink)),
      ],
    );
  }
}

// ================================================================
// 券商風元件
// ================================================================

/// 區塊標題：左側色條 + 標題，右側可放「更多 ›」
class PanelHeader extends StatelessWidget {
  final String label;
  final VoidCallback? onMore;
  final String moreText;
  final EdgeInsets padding;
  const PanelHeader(this.label,
      {super.key,
      this.onMore,
      this.moreText = '更多',
      this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 8)});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                Text(moreText,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.ink3)),
                const Icon(Icons.chevron_right,
                    size: 15, color: AppColors.ink3),
              ]),
            ),
        ],
      ),
    );
  }
}

/// 3-up 指數格：名稱 / 大數字（漲跌色）/ 漲跌+百分比
class IndexCell extends StatelessWidget {
  final String name;
  final double? value;
  final num? change;
  final num? changePct;
  final VoidCallback? onTap;
  const IndexCell({
    super.key,
    required this.name,
    required this.value,
    required this.change,
    required this.changePct,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = change == null ? AppColors.ink : AppColors.forChange(change!);
    final arrow = change == null
        ? ''
        : change! > 0
            ? '▲'
            : change! < 0
                ? '▼'
                : '';
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
              const SizedBox(height: 3),
              Text(value?.toStringAsFixed(2) ?? '--',
                  style: kNum.copyWith(fontSize: 17, color: c)),
              const SizedBox(height: 2),
              Text(
                change == null
                    ? '--'
                    : '$arrow${change!.abs().toStringAsFixed(2)}  ${changePct! >= 0 ? '+' : ''}${changePct!.toStringAsFixed(2)}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kNumSm.copyWith(color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 券商列表列：左色條 + 名稱/代號 + 成交 / 漲跌(％) / 成交量 對齊三欄
class MarketTickerRow extends StatelessWidget {
  final String name;
  final String code;
  final double? price;
  final num? change;
  final num? changePct;
  final String? volumeText;
  final int? rank;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const MarketTickerRow({
    super.key,
    required this.name,
    required this.code,
    required this.price,
    required this.change,
    this.changePct,
    this.volumeText,
    this.rank,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final c = change == null ? AppColors.flat : AppColors.forChange(change!);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          children: [
            Container(width: 3, height: 34, color: c),
            const SizedBox(width: 9),
            if (rank != null) ...[
              SizedBox(
                width: 18,
                child: Text('$rank',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.ink3)),
              ),
              const SizedBox(width: 2),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? code : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 1),
                  Text(code,
                      style: const TextStyle(
                          color: AppColors.ink3, fontSize: 11)),
                ],
              ),
            ),
            SizedBox(
              width: 74,
              child: Text(price?.toStringAsFixed(2) ?? '--',
                  textAlign: TextAlign.right,
                  style: kNum.copyWith(fontSize: 14, color: c)),
            ),
            SizedBox(
              width: 74,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(change == null ? '--' : signed(change!, 2),
                      style: kNumSm.copyWith(color: c)),
                  if (changePct != null)
                    Text(
                        '${changePct! >= 0 ? '+' : ''}${changePct!.toStringAsFixed(2)}%',
                        style: kNumSm.copyWith(color: c)),
                ],
              ),
            ),
            if (volumeText != null)
              SizedBox(
                width: 60,
                child: Text(volumeText!,
                    textAlign: TextAlign.right,
                    style: kNumSm.copyWith(color: AppColors.ink2)),
              ),
          ],
        ),
      ),
    );
  }
}
