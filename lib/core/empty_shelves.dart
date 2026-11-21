import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'i18n.dart';

/// "The shelves are empty", drawn (v0.46.1): a shelf unit with three boards,
/// dashed outlines where boxes would stand, and a box that floats down onto
/// the top board and fades, over and over, like stock waiting to arrive.
/// A screen with nothing on it should still say what to do next.
class EmptyShelves extends StatefulWidget {
  const EmptyShelves({super.key, this.title, this.message, this.actions = const []});

  final String? title;
  final String? message;

  /// Buttons under the message (Pokea mzigo, Ingiza kwa wingi…).
  final List<Widget> actions;

  @override
  State<EmptyShelves> createState() => _EmptyShelvesState();
}

class _EmptyShelvesState extends State<EmptyShelves> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = .55;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 220,
          height: 170,
          child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _ShelfPainter(_c.value))),
        ),
        const SizedBox(height: 16),
        Text(widget.title ?? tr('Rafu ziko tupu'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF16231F))),
        const SizedBox(height: 6),
        Text(
          widget.message ?? tr('Hakuna bidhaa kwenye hisa bado. Ingiza hisa ya mwanzo, au pokea mzigo ukifika: rafu zitajaa hapa kwa aina zake.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF5B6F69)),
        ),
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: widget.actions),
        ],
      ]),
    );
  }
}

class _ShelfPainter extends CustomPainter {
  _ShelfPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final frame = Paint()
      ..color = const Color(0xFFB9CCC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final board = Paint()
      ..color = const Color(0xFF9DB7AE)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final left = w * .1, right = w * .9, top = h * .08, bottom = h * .96;
    // Uprights.
    canvas.drawLine(Offset(left, top), Offset(left, bottom), frame);
    canvas.drawLine(Offset(right, top), Offset(right, bottom), frame);
    final boards = [h * .36, h * .64, h * .92];
    for (final y in boards) {
      canvas.drawLine(Offset(left, y), Offset(right, y), board);
    }
    // Dashed outlines: where the boxes should be.
    final dash = Paint()
      ..color = const Color(0xFFC9D8D2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final slots = [
      (boards[1], left + 14.0, 34.0, 30.0),
      (boards[1], left + 56.0, 26.0, 40.0),
      (boards[2], left + 20.0, 40.0, 34.0),
      (boards[2], right - 70.0, 30.0, 26.0),
      (boards[2], right - 34.0, 22.0, 42.0),
    ];
    for (final s in slots) {
      _dashedRect(canvas, Rect.fromLTWH(s.$2, s.$1 - 3 - s.$4, s.$3, s.$4), dash);
    }
    // The box that floats down onto the top board, lands, and fades.
    final fall = Curves.easeOutBack.transform((t / .55).clamp(0.0, 1.0));
    final fade = t < .75 ? 1.0 : 1 - (t - .75) / .25;
    final bw = 38.0, bh = 30.0;
    final x = w / 2 - bw / 2;
    final yEnd = boards[0] - 3 - bh;
    final y = top - bh + (yEnd - (top - bh)) * fall;
    final box = Paint()..color = const Color(0xFF6FDB9E).withValues(alpha: .85 * fade);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, bh), const Radius.circular(5));
    canvas.save();
    canvas.translate(x + bw / 2, y + bh / 2);
    canvas.rotate((1 - fall) * -.25 * math.pi / 4);
    canvas.translate(-(x + bw / 2), -(y + bh / 2));
    canvas.drawRRect(r, box);
    final tape = Paint()..color = const Color(0xFF1F3B34).withValues(alpha: .35 * fade);
    canvas.drawRect(Rect.fromLTWH(x + bw / 2 - 3, y, 6, bh), tape);
    canvas.restore();
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const d = 5.0, g = 4.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var s = 0.0; s < len; s += d + g) {
        canvas.drawLine(a + dir * s, a + dir * math.min(s + d, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_ShelfPainter old) => old.t != t;
}
