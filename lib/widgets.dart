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
  const IntradayChart(
    this.prices,
    this.volumes,
    this.prevClose, {
    super.key,
    this.times = const [],
    this.regStart,
    this.regEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (prices.length < 2) {
      return const Center(
          child: Text('無分時資料（非交易時段）',
              style: TextStyle(color: AppColors.ink3)));
    }
    final lo = [prevClose, ...prices].reduce((a, b) => a < b ? a : b);
    final hi = [prevClose, ...prices].reduce((a, b) => a > b ? a : b);
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
                prices, prevClose, lo, hi, col, preFrac, postFrac),
            size: Size.infinite,
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
  _IntradayPainter(
      this.p, this.prev, this.lo, this.hi, this.col, this.preFrac, this.postFrac);
  @override
  void paint(Canvas c, Size s) {
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final n = p.length - 1;
    double x(int i) => n == 0 ? 0 : i / n * s.width;
    double y(double v) => s.height - (v - lo) / range * s.height;

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
      o.p != p || o.preFrac != preFrac || o.postFrac != postFrac;
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
  final Widget? trailing;
  const QuoteRow({
    super.key,
    required this.code,
    required this.name,
    required this.q,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final chgColor =
        q?.change == null ? AppColors.surface2 : AppColors.forChange(q!.change!);
    return InkWell(
      onTap: onTap,
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
