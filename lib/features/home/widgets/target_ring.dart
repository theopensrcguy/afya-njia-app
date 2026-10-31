import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';

/// The ring on the today card: how much of the daily sales goal is reached.
///
/// Why a CustomPainter: Flutter's CircularProgressIndicator can't have round
/// ends or a custom thickness behind it. A painter is ~20 lines and draws
/// exactly the design: a light full circle, and a mint arc on top of it.
class TargetRing extends StatelessWidget {
  const TargetRing({
    super.key,
    required this.progress,
    required this.centerText,
    required this.caption,
    this.onTap,
  });

  /// 0.0 to 1.0 (more than 1.0 is drawn as a full ring: goal passed).
  final double progress;
  final String centerText;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$centerText $caption',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 108,
          height: 108,
          child: CustomPaint(
            painter: _RingPainter(progress.clamp(0.0, 1.0)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: inkColor)),
                  Text(caption, style: const TextStyle(fontSize: 10, color: mutedText)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = mintSoft);
    if (progress > 0) {
      // Start at 12 o'clock (-90°) and go clockwise.
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint..color = mintAccent);
    }
  }

  // Only repaint when the number actually changes.
  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
