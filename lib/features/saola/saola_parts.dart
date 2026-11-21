import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/smooth.dart';

/// Shared looks for the Saola console (v0.48.3).
const sInk = Color(0xFF14211D);
const sMuted = Color(0xFF5B6F69);
const sDeep = Color(0xFF0E3B31);
const sMint = Color(0xFF3DDC97);
const sBg = Color(0xFFF2F6F4);
const sLine = Color(0xFFDCE5E1);
const sGood = Color(0xFF1F8A66);
const sBad = Color(0xFFC2412D);
const sWarn = Color(0xFF8A5300);

/// A shop's state: text colour, soft background, dot on dark.
(Color, Color, Color) statusLook(String s) => switch (s) {
      'hai' => (sGood, const Color(0xFFE7F6EF), sMint),
      'inaanza' => (const Color(0xFF2F5FC4), const Color(0xFFEAF0FD), const Color(0xFF8FB3FF)),
      'inapoa' => (sWarn, const Color(0xFFFFF4DC), const Color(0xFFF2B36B)),
      'imelala' => (sBad, const Color(0xFFFBE9E5), const Color(0xFFE88A7A)),
      _ => (sMuted, const Color(0xFFEEF3F1), const Color(0xFFB8C4C0)),
    };

String billingLabel(String s) => switch (s) {
      'trial' => tr('Majaribio'),
      'paid' => tr('Amelipa'),
      'grace' => tr('Siku za nyongeza'),
      'expired' => tr('Malipo yameisha'),
      'free' => tr('Halitozwi'),
      _ => s,
    };

(Color, Color) billingLook(String s) => switch (s) {
      'paid' => (sGood, const Color(0xFFE7F6EF)),
      'trial' => (const Color(0xFF2F5FC4), const Color(0xFFEAF0FD)),
      'grace' => (sWarn, const Color(0xFFFFF4DC)),
      'expired' => (sBad, const Color(0xFFFBE9E5)),
      _ => (sMuted, const Color(0xFFEEF3F1)),
    };

/// Needs Saola about money: ended, in grace, or ending within a week.
bool needsPayment(Map<String, dynamic> shop) {
  final b = (shop['billing'] as Map?) ?? const {};
  final s = '${b['status']}';
  return s == 'grace' || s == 'expired' || (s != 'free' && b['warn'] == true);
}

Widget pill(String text, Color fg, Color bg, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );

Widget sCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: child,
    );

Widget sHeading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: sInk))),
        ?trailing,
      ]),
    );

String seenText(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? tr('hajaonekana') : timeAgo(d);
}

/// 14 days as bars, rising in; tap a bar to read its day. [errorKey] puts a red cap on top.
class DayBars extends StatefulWidget {
  const DayBars({super.key, required this.days, required this.valueKey, required this.color, this.errorKey, this.unit = '', this.height = 120});

  final List<Map<String, dynamic>> days;
  final String valueKey;
  final String? errorKey;
  final Color color;
  final String unit;
  final double height;

  @override
  State<DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<DayBars> {
  int? _at;

  @override
  void didUpdateWidget(DayBars old) {
    super.didUpdateWidget(old);
    if (old.valueKey != widget.valueKey) _at = null;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return SizedBox(height: widget.height);
    final values = [for (final d in days) asInt(d[widget.valueKey])];
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    final at = _at ?? days.length - 1;
    final sel = days[at];
    final errs = widget.errorKey == null ? 0 : asInt(sel[widget.errorKey]);
    final total = values.fold<int>(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: Text('${groupDigits0(values[at])}${widget.unit}', key: ValueKey('$at${widget.valueKey}'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: sInk)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              [
                at == days.length - 1 ? tr('Leo') : '${sel['label']}',
                if (widget.errorKey != null && errs > 0) tr('hitilafu :n', {'n': errs}),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: errs > 0 ? sBad : sMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Text(tr('siku 14: :n', {'n': groupDigits0(total)}), style: const TextStyle(fontSize: 11.5, color: sMuted)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: widget.height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  tick();
                  setState(() => _at = i);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TweenAnimationBuilder<double>(
                      key: ValueKey('${widget.valueKey}$i'),
                      tween: Tween(begin: 0, end: values[i] / max),
                      duration: Motion.of(context, Duration(milliseconds: 420 + i * 30)),
                      curve: Motion.curve,
                      builder: (_, v, _) {
                        final h = (widget.height - 18) * v;
                        final e = widget.errorKey == null || values[i] == 0 ? 0.0 : (asInt(d[widget.errorKey]) / values[i]).clamp(0.0, 1.0) * h;
                        return Container(
                          height: h < 3 ? 3 : h,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: i == at ? widget.color : widget.color.withValues(alpha: .28),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.topCenter,
                          child: e > 0 ? Container(height: e < 2 ? 2 : e, color: sBad) : null,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 12,
                      child: i % 2 == (days.length - 1) % 2
                          ? FittedBox(child: Text('${d['label']}'.split('/').first, style: TextStyle(fontSize: 10, color: i == at ? sInk : sMuted, fontWeight: i == at ? FontWeight.w800 : FontWeight.w500)))
                          : null,
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

String groupDigits0(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// A page that rises in (the Saola screens open over home).
Route<R> riseRoute<R>(Widget page) => PageRouteBuilder<R>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Motion.curve, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(c), child: child),
        );
      },
    );
