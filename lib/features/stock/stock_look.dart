import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import '../../models/product.dart';

/// How a product LOOKS everywhere (list, Rafu, home): one state, one colour,
/// one pack drawing. The same states and order as the web (StockInsightService).

/// Worst first: each product is in exactly one.
const stockStates = ['expired', 'out', 'low', 'expiring', 'ok'];

class StateLook {
  const StateLook(this.label, this.color, this.soft, this.ink);
  final String label;
  final Color color; // drawings, dots, bars
  final Color soft; // backgrounds
  final Color ink; // text on soft (4.5:1)
}

const stateLooks = {
  'ok': StateLook('Sawa', Color(0xFF1F8A66), Color(0xFFE7F6EF), Color(0xFF0E5A44)),
  'expiring': StateLook('Inaisha muda', Color(0xFFE39B2E), Color(0xFFFDF1E3), Color(0xFF7A4A12)),
  'low': StateLook('Chache', Color(0xFF4D7FE0), Color(0xFFEAF0FD), Color(0xFF2F5FC4)),
  'out': StateLook('Imeisha', Color(0xFFC2412D), Color(0xFFFBE9E5), Color(0xFFA8321F)),
  'expired': StateLook('Zimeisha muda', Color(0xFF6E5A9E), Color(0xFFF0ECF7), Color(0xFF5B4790)),
};

String stateOf(Map<String, dynamic> p) => switch (p) {
      _ when p['is_expired'] == true => 'expired',
      _ when p['is_out'] == true => 'out',
      _ when p['is_low'] == true => 'low',
      _ when p['is_expiring'] == true => 'expiring',
      _ => 'ok',
    };

List<ProductUnit> unitsOf(Map<String, dynamic> p) =>
    ((p['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList()
      ..sort((a, b) => a.baseQuantity.compareTo(b.baseQuantity));

/// "33 kadi + 6", or "Imeisha".
String stockText(Map<String, dynamic> p) {
  final n = asInt(p['on_hand']);
  if (n <= 0) return tr('Imeisha');
  return describeStock(n, unitsOf(p));
}

/// The price people know it by: the pack unit (kadi), else the base unit.
String mainPrice(Map<String, dynamic> p) {
  if (p['needs_price'] == true) return tr('Haina bei');
  final units = unitsOf(p);
  if (units.isEmpty) return '';
  final u = units.length > 1 ? units[1] : units.first;
  if (u.price <= 0) return tr('Haina bei');
  return '${formatTsh(u.price)} / ${unitLabel(u.name)}';
}

/// How full, against the reorder level: 3× the level reads as a full bar.
double levelOf(Map<String, dynamic> p) {
  final n = asInt(p['on_hand']);
  final r = asInt(p['reorder_level']);
  if (n <= 0) return 0;
  if (r <= 0) return .75;
  return (n / (r * 3)).clamp(.06, 1).toDouble();
}

/// Packs drawn on Rafu: 3 plenty, 2 fine, 1 low, 0 out (a dashed ghost).
int packsOf(Map<String, dynamic> p) {
  final n = asInt(p['on_hand']);
  final r = asInt(p['reorder_level']);
  if (n <= 0) return 0;
  if (n <= r) return 1;
  if (r <= 0 || n > r * 2) return 3;
  return 2;
}

int? daysToExpiry(Map<String, dynamic> p) {
  final d = parseDate(p['next_expiry']);
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// "siku 21", "miezi 7", "mwaka 1.5".
String spanText(int days) {
  if (days <= 60) return tr('siku :n', {'n': days});
  final months = days / 30.4;
  if (months < 12) return tr('miezi :n', {'n': months.round()});
  final years = (months / 12 * 2).round() / 2;
  return tr('mwaka :n', {'n': years == years.roundToDouble() ? years.toInt() : years});
}

/// Expiry colour in Rafu's "Muda" mode.
Color expiryColor(Map<String, dynamic> p) {
  if (p['is_expired'] == true) return const Color(0xFF6E5A9E);
  final d = daysToExpiry(p);
  if (d == null) return const Color(0xFFB8C4C0);
  if (d <= 30) return const Color(0xFFC2412D);
  if (d <= 90) return const Color(0xFFE39B2E);
  return const Color(0xFF1F8A66);
}

/// The product's form as a pack: tablet → box, capsule → jar, syrup → bottle,
/// injection → vial, cream → tube, anything else → carton.
class PackIcon extends StatelessWidget {
  const PackIcon({super.key, required this.form, required this.color, this.size = 26, this.empty = false, this.fill});

  final String? form;
  final Color color;
  final double size;
  final bool empty;
  final Color? fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size * 1.15),
        painter: _PackPainter(form ?? 'other', color, empty, fill),
      );
}

class _PackPainter extends CustomPainter {
  _PackPainter(this.form, this.color, this.empty, this.fill);
  final String form;
  final Color color;
  final bool empty;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path();
    switch (form) {
      case 'capsule': // jar
        path.addRRect(RRect.fromLTRBR(w * .28, h * .06, w * .72, h * .22, const Radius.circular(2)));
        path.addRRect(RRect.fromLTRBR(w * .18, h * .22, w * .82, h * .94, Radius.circular(w * .14)));
      case 'syrup': // bottle
        path
          ..moveTo(w * .40, h * .05)
          ..lineTo(w * .60, h * .05)
          ..lineTo(w * .60, h * .22)
          ..lineTo(w * .78, h * .36)
          ..lineTo(w * .78, h * .94)
          ..lineTo(w * .22, h * .94)
          ..lineTo(w * .22, h * .36)
          ..lineTo(w * .40, h * .22)
          ..close();
      case 'injection': // vial
        path.addRRect(RRect.fromLTRBR(w * .34, h * .05, w * .66, h * .18, const Radius.circular(2)));
        path.addRRect(RRect.fromLTRBR(w * .28, h * .18, w * .72, h * .94, Radius.circular(w * .1)));
      case 'cream': // tube
        path
          ..moveTo(w * .22, h * .30)
          ..lineTo(w * .78, h * .30)
          ..lineTo(w * .70, h * .94)
          ..lineTo(w * .30, h * .94)
          ..close();
        path.addRect(Rect.fromLTRB(w * .40, h * .08, w * .60, h * .30));
      case 'tablet': // box
        path.addRRect(RRect.fromLTRBR(w * .14, h * .14, w * .86, h * .92, Radius.circular(w * .08)));
      default: // carton
        path
          ..moveTo(w * .10, h * .30)
          ..lineTo(w * .50, h * .12)
          ..lineTo(w * .90, h * .30)
          ..lineTo(w * .90, h * .80)
          ..lineTo(w * .50, h * .96)
          ..lineTo(w * .10, h * .80)
          ..close();
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * .06)
      ..strokeJoin = StrokeJoin.round;
    if (!empty) {
      canvas.drawPath(path, Paint()..color = fill ?? color.withValues(alpha: .18));
      canvas.drawPath(path, stroke);
      // A label band, like the printed label on a real pack.
      final band = Rect.fromLTRB(w * .32, h * .52, w * .68, h * .66);
      canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(1.5)), Paint()..color = Colors.white.withValues(alpha: .9));
    } else {
      // Out of stock: a dashed outline where the pack should be.
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), stroke);
          d += 5.5;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PackPainter o) => o.form != form || o.color != color || o.empty != empty || o.fill != fill;
}
