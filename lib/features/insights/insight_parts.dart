import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/smooth.dart';

/// Shared pieces of the insight screens (v0.45, from the canvas, screens 5–9):
/// a cached loader, money in short form, change badges, and the charts.

const kInk = Color(0xFF14211D);
const kMuted = Color(0xFF5B6F69);
const kPrimary = Color(0xFF12644E);
const kDeep = Color(0xFF0E3B31);
const kMint = Color(0xFF3DDC97);
const kBg = Color(0xFFF2F6F4);
const kGood = Color(0xFF0E5A44);
const kGoodSoft = Color(0xFFE7F6EF);
const kBad = Color(0xFFA8321F);
const kBadSoft = Color(0xFFFBE9E5);

/// "9.86M", "410K", "7,720": amounts that fit a tile.
String shortMoney(int v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 1000000) return '$sign${(a / 1000000).toStringAsFixed(a >= 10000000 ? 1 : 2)}M';
  if (a >= 100000) return '$sign${(a / 1000).round()}K';
  return '$sign${formatTsh(a).replaceFirst('TSh ', '')}';
}

String tshShort(int v, {bool hidden = false}) => hidden ? tr('TSh ••••••') : 'TSh ${shortMoney(v)}';

/// A white card with the screens' radius.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color = Colors.white, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk))),
        ?trailing,
      ]);
}

/// "↑ 18% kuliko jana": green when it went the good way. For costs, up is bad.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.delta, this.than, this.upIsGood = true, this.onDark = false, this.diff});
  final num? delta;
  final num? diff; // a count difference instead of %: "+4"
  final String? than;
  final bool upIsGood;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final v = diff ?? delta;
    if (v == null) return const SizedBox.shrink();
    final up = v > 0;
    final flat = v == 0;
    final good = flat ? null : (up == upIsGood);
    final arrow = flat ? '=' : (up ? '↑' : '↓');
    final amount = diff != null ? '${diff! > 0 ? '+' : ''}$diff' : '${delta!.abs() >= 10 ? delta!.abs().round() : delta!.abs()}%';
    final text = [arrow, amount, ?than].join(' ');
    final (bg, fg) = onDark
        ? (Colors.white.withValues(alpha: .1), good == false ? const Color(0xFFF9B4A6) : const Color(0xFF8FE6BE))
        : (good == null ? (const Color(0xFFEEF3F1), kMuted) : good ? (kGoodSoft, kGood) : (kBadSoft, kBad));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Opens on the last answer for [path] (ApiCache) and refreshes quietly;
/// a skeleton the first time; the old answer stays if a refresh fails.
class CachedJson extends StatefulWidget {
  const CachedJson({
    super.key,
    required this.api,
    required this.path,
    this.query,
    required this.builder,
    required this.skeleton,
    this.refreshTick = 0,
  });

  final ApiClient api;
  final String path;
  final Map<String, String>? query;
  final Widget Function(BuildContext, Map<String, dynamic> data, Future<void> Function() reload) builder;
  final Widget skeleton;
  final int refreshTick;

  @override
  State<CachedJson> createState() => _CachedJsonState();
}

class _CachedJsonState extends State<CachedJson> {
  Map<String, dynamic>? _data;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _peek();
    _load();
  }

  void _peek() {
    final c = ApiCache.peek(widget.api, widget.path, query: widget.query);
    _data = c is Map<String, dynamic> ? c : null;
  }

  @override
  void didUpdateWidget(CachedJson old) {
    super.didUpdateWidget(old);
    final queryChanged = '${old.query}' != '${widget.query}' || old.path != widget.path;
    if (queryChanged) {
      // A new period: show what we had for it (if anything), else keep the old one dimmed below.
      final c = ApiCache.peek(widget.api, widget.path, query: widget.query);
      if (c is Map<String, dynamic>) _data = c;
    }
    if (queryChanged || old.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    final my = ++_req;
    try {
      final d = await ApiCache.fetch(widget.api, widget.path, query: widget.query) as Map<String, dynamic>;
      if (mounted && my == _req) setState(() => (_data = d, _error = null));
    } on ApiException catch (e) {
      if (mounted && my == _req) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      if (_error != null) {
        return InsightCard(
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: kMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: const TextStyle(color: kInk))),
            TextButton(onPressed: _load, child: const T('Jaribu tena')),
          ]),
        );
      }
      return widget.skeleton;
    }
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      child: KeyedSubtree(key: ValueKey('${widget.path}${widget.query}'), child: widget.builder(context, d, _load)),
    );
  }
}

// ---------------------------------------------------------------- charts

/// A half-ring gauge (0–100+%), drawn in on first show.
class SemiGauge extends StatelessWidget {
  const SemiGauge({super.key, required this.pct, this.width = 104, this.stroke = 10, this.color = kMint, this.track = const Color(0x1FFFFFFF), this.label, this.caption, this.onDark = true});
  final int? pct;
  final double width;
  final double stroke;
  final Color color;
  final Color track;
  final String? label;
  final String? caption;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final h = width / 2 + stroke / 2 + 4;
    return SizedBox(
      width: width,
      height: h,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ((pct ?? 0) / 100).clamp(0, 1).toDouble()),
        duration: Motion.of(context, Motion.slow),
        curve: Motion.curve,
        builder: (_, v, _) => CustomPaint(
          painter: _SemiPainter(v, stroke, color, track),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label ?? (pct == null ? '—' : '$pct%'),
                  style: TextStyle(fontSize: width > 120 ? 22 : 16, fontWeight: FontWeight.w700, color: onDark ? Colors.white : kInk)),
              if (caption != null) Text(caption!, style: TextStyle(fontSize: 10, color: onDark ? const Color(0xFFB7D3C9) : kMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SemiPainter extends CustomPainter {
  _SemiPainter(this.v, this.stroke, this.color, this.track);
  final double v;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(s.width / 2, s.height - stroke / 2 - 2), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    if (v > 0) canvas.drawArc(rect, math.pi, math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_SemiPainter o) => o.v != v || o.color != color;
}

/// A ring of shares (flat ends, clear gaps, at least 3% each).
class ShareRing extends StatelessWidget {
  const ShareRing({super.key, required this.values, required this.colors, this.size = 120, this.stroke = 14, this.focus, this.center, this.half = false});
  final List<num> values;
  final List<Color> colors;
  final double size;
  final double stroke;
  final int? focus;
  final Widget? center;
  final bool half;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: half ? size / 2 + stroke : size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.of(context, Motion.slow),
        curve: Motion.curve,
        builder: (_, t, _) => CustomPaint(
          painter: _RingPainter(values, colors, stroke, focus, t, half),
          child: Align(alignment: half ? Alignment.bottomCenter : Alignment.center, child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.values, this.colors, this.stroke, this.focus, this.t, this.half);
  final List<num> values;
  final List<Color> colors;
  final double stroke;
  final int? focus;
  final double t;
  final bool half;

  @override
  void paint(Canvas canvas, Size s) {
    final total = values.fold<num>(0, (a, b) => a + b);
    final r = s.width / 2 - stroke / 2 - 2;
    final c = half ? Offset(s.width / 2, s.height - stroke / 2) : s.center(Offset.zero);
    final sweepAll = (half ? math.pi : 2 * math.pi) * t;
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      canvas.drawArc(rect, half ? math.pi : -math.pi / 2, half ? math.pi : 2 * math.pi, false, base..color = const Color(0xFFEEF3F1));
      return;
    }
    final shares = values.map((v) => v <= 0 ? 0.0 : math.max(v / total, .03)).toList();
    final sum = shares.fold<double>(0, (a, b) => a + b);
    var start = half ? math.pi : -math.pi / 2;
    const gap = .05;
    for (var i = 0; i < shares.length; i++) {
      final sweep = shares[i] / sum * sweepAll;
      if (sweep > gap) {
        canvas.drawArc(rect, start + gap / 2, sweep - gap, false,
            base
              ..color = colors[i % colors.length].withValues(alpha: focus != null && focus != i ? .25 : 1)
              ..strokeWidth = focus == i ? stroke + 4 : stroke);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.t != t || o.focus != focus || o.values != values;
}

/// Running totals across a month: this one (solid), the last (dashed), an
/// optional forecast to the month's end (dotted) and a target line.
class MonthLines extends StatelessWidget {
  const MonthLines({
    super.key,
    required this.current,
    this.previous,
    required this.daysInMonth,
    this.color = kPrimary,
    this.forecastTo,
    this.target,
    this.tip,
    this.height = 170,
  });

  final List<int> current;
  final List<int>? previous;
  final int daysInMonth;
  final Color color;
  final int? forecastTo;
  final int? target;
  final String? tip;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.of(context, Motion.slow),
        curve: Motion.curve,
        builder: (_, t, _) => CustomPaint(
          painter: _LinesPainter(current, previous, daysInMonth, color, forecastTo, target, tip, t),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.cur, this.prev, this.days, this.color, this.forecastTo, this.target, this.tip, this.t);
  final List<int> cur;
  final List<int>? prev;
  final int days;
  final Color color;
  final int? forecastTo;
  final int? target;
  final String? tip;
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    const top = 26.0, bottom = 18.0;
    final h = s.height - top - bottom;
    final maxV = [
      ...cur, ...?prev, ?forecastTo, ?target,
    ].fold<int>(1, (a, b) => math.max(a, b)).toDouble();
    double x(int i) => days <= 1 ? 0 : i / (days - 1) * s.width;
    double y(num v) => top + h - (v / maxV) * h;

    final grid = Paint()..color = const Color(0xFFEEF3F1);
    for (var k = 0; k <= 2; k++) {
      canvas.drawLine(Offset(0, top + h * k / 2), Offset(s.width, top + h * k / 2), grid);
    }
    if (target != null) {
      _dashed(canvas, Offset(0, y(target!)), Offset(s.width, y(target!)), Paint()
        ..color = const Color(0xFFC2412D)
        ..strokeWidth = 1.5, 3, 4);
      _text(canvas, tr('lengo :a', {'a': shortMoney(target!)}), Offset(s.width, y(target!) - 14), const Color(0xFFA8321F), right: true);
    }
    if (prev != null && prev!.isNotEmpty) {
      final p = Path()..moveTo(x(0), y(prev![0]));
      for (var i = 1; i < prev!.length; i++) {
        p.lineTo(x(i), y(prev![i]));
      }
      _dashPath(canvas, p, Paint()
        ..color = const Color(0xFFB8C4C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    if (cur.isEmpty) return;
    final shown = math.max(1, (cur.length * t).ceil());
    final line = Path()..moveTo(x(0), y(cur[0]));
    final area = Path()
      ..moveTo(x(0), top + h)
      ..lineTo(x(0), y(cur[0]));
    for (var i = 1; i < shown; i++) {
      line.lineTo(x(i), y(cur[i]));
      area.lineTo(x(i), y(cur[i]));
    }
    area
      ..lineTo(x(shown - 1), top + h)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .08));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    final last = Offset(x(shown - 1), y(cur[shown - 1]));
    if (forecastTo != null && t >= 1) {
      _dashed(canvas, last, Offset(s.width, y(forecastTo!)), Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round, 2, 6);
    }
    canvas.drawCircle(last, 6, Paint()..color = Colors.white);
    canvas.drawCircle(last, 6, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    if (tip != null && t >= 1) {
      final tp = TextPainter(text: TextSpan(text: tip, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
      final w = tp.width + 16;
      final left = (last.dx - w / 2).clamp(0.0, s.width - w);
      final topY = math.max(0.0, last.dy - 34);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, topY, w, 24), const Radius.circular(8)), Paint()..color = kInk);
      tp.paint(canvas, Offset(left + 8, topY + 5));
    }
    _text(canvas, '1', Offset(0, s.height - 13), kMuted);
    _text(canvas, '$days', Offset(s.width, s.height - 13), kMuted, right: true);
  }

  void _text(Canvas c, String s, Offset at, Color color, {bool right = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, right ? at - Offset(tp.width, 0) : at);
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, double on, double off) {
    final d = (b - a).distance;
    if (d == 0) return;
    final dir = (b - a) / d;
    for (var s = 0.0; s < d; s += on + off) {
      c.drawLine(a + dir * s, a + dir * math.min(s + on, d), p);
    }
  }

  void _dashPath(Canvas c, Path p, Paint paint) {
    for (final m in p.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        c.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LinesPainter o) => o.t != t || o.cur != cur || o.color != color;
}

/// A grey placeholder card with lines.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, this.height = 160});
  final double height;

  @override
  Widget build(BuildContext context) => InsightCard(
        child: SizedBox(
          height: height - 36,
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Skeleton(width: 140, height: 14),
            SizedBox(height: 14),
            Skeleton(width: 200, height: 26),
            Spacer(),
            Skeleton(height: 10),
          ]),
        ),
      );
}
