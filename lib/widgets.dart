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
      return Center(
          child: Text('無分時資料（非交易時段）',
              style: TextStyle(color: AppColors.ink3)));
    }
    final useTimeAll = times.length == prices.length && times.length > 1;

    // 主圖只畫「正常盤」時段的點；盤前不顯示，盤後另外用下面的專區呈現，
    // 不混在同一張圖裡（之前盤前盤後會擠在主圖兩側，容易看錯）。
    var regPrices = prices;
    var regVolumes = volumes;
    var regTimes = times;
    var prePrices = const <double>[];
    var preTimes = const <int>[];
    var postPrices = const <double>[];
    var postTimes = const <int>[];
    if (useTimeAll && regStart != null && regEnd != null) {
      final rp = <double>[], rv = <double>[], rt = <int>[];
      final ep = <double>[], et = <int>[];
      final pp = <double>[], pt = <int>[];
      for (var i = 0; i < prices.length; i++) {
        final t = times[i];
        if (t >= regStart! && t <= regEnd!) {
          rp.add(prices[i]);
          rv.add(volumes[i]);
          rt.add(t);
        } else if (t < regStart!) {
          ep.add(prices[i]);
          et.add(t);
        } else {
          pp.add(prices[i]);
          pt.add(t);
        }
      }
      if (rp.length >= 2) {
        regPrices = rp;
        regVolumes = rv;
        regTimes = rt;
      }
      prePrices = ep;
      preTimes = et;
      postPrices = pp;
      postTimes = pt;
    }

    if (regPrices.length < 2) {
      // 還沒開盤：只有試搓資料的話單獨顯示盤前專區，不要整個空白
      if (prePrices.length > 1) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _PrePostSection(
              '盤前試搓', AppColors.warn, prePrices, preTimes, prevClose),
        );
      }
      return Center(
          child: Text('無分時資料（非交易時段）',
              style: TextStyle(color: AppColors.ink3)));
    }

    // 昨收固定畫在正中間：以昨收為中心，取「離昨收最遠的偏移量」對稱
    // 抓上下界，這樣虛線永遠在圖表正中央，不會因為股價漲多跌多而偏移。
    final span = [...regPrices, ...cdp.values];
    final maxDev = span
        .map((v) => (v - prevClose).abs())
        .fold<double>(1e-6, (a, b) => a > b ? a : b);
    final lo = prevClose - maxDev;
    final hi = prevClose + maxDev;
    final up = regPrices.last >= prevClose;
    final col = up ? AppColors.up : AppColors.down;

    final useTime = regTimes.length == regPrices.length && regTimes.length > 1;
    final dataMin = useTime ? regTimes.first : 0;
    final dataMax = useTime ? regTimes.last : regPrices.length - 1;
    // 軸固定成整個交易時段（開盤~收盤），不會隨資料愈收愈多而一直重新
    // 縮放 —— 這樣線只會畫到「現在」，右邊留白隨時間慢慢被填滿。
    final t0 = useTime && regStart != null && regStart! < dataMin
        ? regStart!
        : dataMin;
    final tN = useTime && regEnd != null && regEnd! > dataMax
        ? regEnd!
        : dataMax;

    return Column(
      children: [
        if (prePrices.length > 1)
          _PrePostSection(
              '盤前試搓', AppColors.warn, prePrices, preTimes, prevClose),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('高 ${hi.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.up)),
              Text('昨收 ${prevClose.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3)),
              Text('低 ${lo.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.down)),
            ],
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: _IntradayPainter(regPrices, useTime ? regTimes : const [],
                t0, tN, prevClose, lo, hi, col, 0.0, 1.0, cdp),
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
            painter: _VolPainter(regVolumes, regPrices, prevClose,
                useTime ? regTimes : const [], t0, tN),
            size: Size.infinite,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(useTime ? _hm(t0) : '',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.ink3)),
              Text(useTime ? _hm(tN) : '',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.ink3)),
            ],
          ),
        ),
        if (postPrices.length > 1)
          _PrePostSection(
              '盤後專區', AppColors.accent, postPrices, postTimes, regPrices.last),
      ],
    );
  }

  static String _hm(int sec) {
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// 盤前試搓／盤後專區：跟主圖分開一張小卡呈現，不擠在同一張圖裡
class _PrePostSection extends StatelessWidget {
  final String label;
  final Color badgeColor;
  final List<double> prices;
  final List<int> times;
  final double refPrice; // 漲跌基準（盤前用昨收、盤後用正常盤收盤）
  const _PrePostSection(
      this.label, this.badgeColor, this.prices, this.times, this.refPrice);

  @override
  Widget build(BuildContext context) {
    final last = prices.last;
    final hiP = prices.reduce((a, b) => a > b ? a : b);
    final loP = prices.reduce((a, b) => a < b ? a : b);
    final chg = last - refPrice;
    final chgPct = refPrice == 0 ? 0.0 : chg / refPrice * 100;
    final c = AppColors.forChange(chg);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: badgeColor,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(last.toStringAsFixed(2),
                style: kNum.copyWith(fontSize: 16, color: c)),
            const SizedBox(width: 8),
            Text(
                '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}'
                '（${chgPct >= 0 ? '+' : ''}${chgPct.toStringAsFixed(2)}%）',
                style: TextStyle(fontSize: 12, color: c)),
            const Spacer(),
            Text(IntradayChart._hm(times.last),
                style: TextStyle(fontSize: 10, color: AppColors.ink3)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
              height: 34, child: Sparkline(prices, baseline: refPrice)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('高 ${hiP.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 10, color: AppColors.ink3)),
              Text('低 ${loP.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 10, color: AppColors.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntradayPainter extends CustomPainter {
  final List<double> p;
  final List<int> times; // 與 p 等長時，依「現在時間 / 全時段」定位 x；否則退回等分
  final int t0, tN; // 固定時段（開盤~收盤）
  final double prev, lo, hi;
  final Color col;
  final double preFrac, postFrac;
  final Map<String, double> cdp;
  _IntradayPainter(this.p, this.times, this.t0, this.tN, this.prev, this.lo,
      this.hi, this.col, this.preFrac, this.postFrac, this.cdp);
  @override
  void paint(Canvas c, Size s) {
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final n = p.length - 1;
    final useTime = times.length == p.length && tN != t0;
    double x(int i) => useTime
        ? (times[i] - t0) / (tN - t0) * s.width
        : (n == 0 ? 0 : i / n * s.width);
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
      o.t0 != t0 ||
      o.tN != tN ||
      o.preFrac != preFrac ||
      o.postFrac != postFrac ||
      o.cdp != cdp;
}

class _VolPainter extends CustomPainter {
  final List<double> v;
  final List<double> p;
  final double prev;
  final List<int> times;
  final int t0, tN;
  _VolPainter(this.v, this.p, this.prev, this.times, this.t0, this.tN);
  @override
  void paint(Canvas c, Size s) {
    if (v.isEmpty) return;
    final mx = v.reduce((a, b) => a > b ? a : b);
    if (mx <= 0) return;
    final n = v.length - 1;
    final useTime = times.length == v.length && tN != t0;
    // 依資料點的平均時間間隔換算柱寬（固定時段軸下，柱子寬度不再隨資料
    // 筆數變動而伸縮）
    final avgDt =
        useTime && v.length > 1 ? (times.last - times.first) / n : 60;
    final slot = useTime
        ? s.width * avgDt / (tN - t0)
        : (n == 0 ? s.width : s.width / v.length);
    double x(int i) => useTime
        ? (times[i] - t0) / (tN - t0) * s.width
        : (n == 0 ? 0 : i / n * s.width);
    for (var i = 0; i < v.length; i++) {
      final h = v[i] / mx * s.height;
      final rising = i == 0 || p[i] >= (i > 0 ? p[i - 1] : prev);
      c.drawRect(
        Rect.fromLTWH(x(i), s.height - h, slot * 0.7, h),
        Paint()
          ..color = (rising ? AppColors.up : AppColors.down)
              .withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_VolPainter o) =>
      o.v != v || o.t0 != t0 || o.tN != tN;
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
      return Center(
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
                      style: TextStyle(
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
                      style: TextStyle(
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
                  if (q?.isLimitUp == true || q?.isLimitDown == true) ...[
                    LimitBadge(q!.isLimitUp),
                    const SizedBox(height: 3),
                  ],
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
            style: TextStyle(color: AppColors.ink3, fontSize: 12)),
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
              style: TextStyle(
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
                        TextStyle(fontSize: 12, color: AppColors.ink3)),
                Icon(Icons.chevron_right,
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
                  style: TextStyle(fontSize: 11, color: AppColors.ink2)),
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
  final bool isLimitUp;
  final bool isLimitDown;
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
    this.isLimitUp = false,
    this.isLimitDown = false,
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
                    style: TextStyle(
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
                      style: TextStyle(
                          color: AppColors.ink3, fontSize: 11)),
                ],
              ),
            ),
            SizedBox(
              width: 74,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isLimitUp || isLimitDown) LimitBadge(isLimitUp),
                  Text(price?.toStringAsFixed(2) ?? '--',
                      textAlign: TextAlign.right,
                      style: kNum.copyWith(fontSize: 14, color: c)),
                ],
              ),
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

/// 多檔標的走勢比較（以區間起點為 0% 正規化畫在同一張圖）
class CompareSeries {
  final String label;
  final Color color;
  final List<double> pct; // 相對區間起點的漲跌 %
  const CompareSeries(this.label, this.color, this.pct);
}

class CompareChart extends StatelessWidget {
  final List<CompareSeries> series;
  const CompareChart(this.series, {super.key});

  @override
  Widget build(BuildContext context) {
    final usable = series.where((s) => s.pct.length > 1).toList();
    if (usable.isEmpty) {
      return Center(
          child: Text('無資料', style: TextStyle(color: AppColors.ink3)));
    }
    final all = [for (final s in usable) ...s.pct, 0.0];
    final lo = all.reduce((a, b) => a < b ? a : b);
    final hi = all.reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _ComparePainter(usable, lo, hi),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in usable)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(
                    '${s.label}  ${signed(s.pct.isEmpty ? 0 : s.pct.last, 2)}%',
                    style: TextStyle(
                        fontSize: 12, color: s.color, fontWeight: FontWeight.w600)),
              ]),
          ],
        ),
      ],
    );
  }
}

class _ComparePainter extends CustomPainter {
  final List<CompareSeries> series;
  final double lo, hi;
  _ComparePainter(this.series, this.lo, this.hi);
  @override
  void paint(Canvas c, Size s) {
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    double y(double v) => s.height - (v - lo) / range * s.height;

    // 0% 基準虛線
    final zeroY = y(0);
    final dash = Paint()
      ..color = AppColors.ink3
      ..strokeWidth = 1;
    for (double dx = 0; dx < s.width; dx += 6) {
      c.drawLine(Offset(dx, zeroY), Offset(dx + 3, zeroY), dash);
    }

    for (final ser in series) {
      final p = ser.pct;
      final n = p.length - 1;
      if (n <= 0) continue;
      double x(int i) => i / n * s.width;
      final path = ui.Path()..moveTo(x(0), y(p[0]));
      for (var i = 1; i < p.length; i++) {
        path.lineTo(x(i), y(p[i]));
      }
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = ser.color);
    }
  }

  @override
  bool shouldRepaint(_ComparePainter o) => o.series != series;
}

/// 漲停／跌停徽章：實色底＋淡光暈，比一般漲跌字更醒目
class LimitBadge extends StatelessWidget {
  final bool up;
  const LimitBadge(this.up, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = up ? AppColors.up : AppColors.down;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
              color: c.withValues(alpha: 0.55), blurRadius: 7, spreadRadius: 0.5),
        ],
      ),
      child: Text(up ? '漲停' : '跌停',
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1)),
    );
  }
}

/// 盤前試搓卡：TWSE/Yahoo 都沒有公開的盤前逐筆歷史，只能顯示「現在」
/// 這一筆試搓價（跟五檔同一份即時資料），不硬畫假的走勢圖。
class PreOpenCard extends StatelessWidget {
  final double? price;
  final double? prevClose;
  final String clock;
  const PreOpenCard(
      {super.key, required this.price, required this.prevClose, required this.clock});

  @override
  Widget build(BuildContext context) {
    final chg =
        (price != null && prevClose != null) ? price! - prevClose! : null;
    final chgPct = (chg != null && (prevClose ?? 0) != 0)
        ? chg / prevClose! * 100
        : null;
    final c = chg == null ? AppColors.ink3 : AppColors.forChange(chg);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5)),
              child: const Text('盤前試搓',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.warn,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            Text(price?.toStringAsFixed(2) ?? '--',
                style: kNum.copyWith(fontSize: 32, color: c)),
            const SizedBox(height: 4),
            Text(
                chg == null
                    ? '－'
                    : '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}'
                        '（${chgPct! >= 0 ? '+' : ''}${chgPct.toStringAsFixed(2)}%）',
                style: TextStyle(fontSize: 13, color: c)),
            const SizedBox(height: 10),
            Text('$clock 試搓・09:00 開盤後開始畫分時走勢',
                style: TextStyle(fontSize: 11, color: AppColors.ink3)),
          ],
        ),
      ),
    );
  }
}

/// 資料只在第一次 build 時抓一次；父層之後不管重建幾次（例如報價每秒
/// 輪詢）都不會讓這裡重新變成 loading 狀態，避免畫面一直閃/跳動。
class CachedFutureBuilder<T> extends StatefulWidget {
  final Future<T> Function() future;
  final Widget Function(BuildContext, AsyncSnapshot<T>) builder;
  const CachedFutureBuilder(
      {super.key, required this.future, required this.builder});
  @override
  State<CachedFutureBuilder<T>> createState() =>
      _CachedFutureBuilderState<T>();
}

class _CachedFutureBuilderState<T> extends State<CachedFutureBuilder<T>> {
  late final Future<T> _f = widget.future();
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<T>(future: _f, builder: widget.builder);
}
