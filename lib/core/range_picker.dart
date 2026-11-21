import 'package:flutter/material.dart';

import 'format.dart';
import 'i18n.dart';
import 'smooth.dart';

/// Pick one day or a period by tapping, never typing (v0.46.1).
///
/// Quick choices on top (Leo, Jana, Wiki hii, Mwezi huu, Mwezi uliopita,
/// Siku 30), then a month calendar: the first tap is the start, the second
/// the end (tap the same day twice, or press Onyesha after one tap, for a
/// single day). Days after [last] can't be picked. At most [maxDays].
/// Returns the range with both ends at midnight, or null when closed.
Future<DateTimeRange?> pickDayOrRange(
  BuildContext context, {
  required DateTime last,
  DateTime? first,
  DateTimeRange? initial,
  int maxDays = 93,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _RangeSheet(last: _d(last), first: _d(first ?? DateTime(2024)), initial: initial, maxDays: maxDays),
  );
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

const _ink = Color(0xFF16231F);
const _deep = Color(0xFF1F3B34);
const _mint = Color(0xFF6FDB9E);
const _muted = Color(0xFF5B6F69);

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({required this.last, required this.first, required this.initial, required this.maxDays});

  final DateTime last;
  final DateTime first;
  final DateTimeRange? initial;
  final int maxDays;

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late DateTime _start = _d(widget.initial?.start ?? widget.last);
  DateTime? _end; // null while choosing the second day
  late DateTime _month = DateTime(_start.year, _start.month);

  @override
  void initState() {
    super.initState();
    final e = widget.initial?.end;
    _end = e == null ? _start : _d(e);
  }

  void _tap(DateTime day) {
    tick();
    setState(() {
      if (_end != null) {
        // A fresh choice: this day is the start.
        _start = day;
        _end = null;
      } else if (day.isBefore(_start)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
      final end = _end;
      if (end != null && end.difference(_start).inDays >= widget.maxDays) {
        _start = end.subtract(Duration(days: widget.maxDays - 1));
      }
    });
  }

  void _preset(DateTime a, DateTime b) {
    tick();
    final s = a.isBefore(widget.first) ? widget.first : a;
    final e = b.isAfter(widget.last) ? widget.last : b;
    Navigator.of(context).pop(DateTimeRange(start: s, end: e));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.last;
    final monday = t.subtract(Duration(days: t.weekday - 1));
    final prev = DateTime(t.year, t.month - 1);
    final presets = <(String, DateTime, DateTime)>[
      (tr('Leo'), t, t),
      (tr('Jana'), t.subtract(const Duration(days: 1)), t.subtract(const Duration(days: 1))),
      (tr('Wiki hii'), monday, t),
      (tr('Mwezi huu'), DateTime(t.year, t.month), t),
      (tr('Mwezi uliopita'), prev, DateTime(t.year, t.month, 0)),
      (tr('Siku 30'), t.subtract(const Duration(days: 29)), t),
    ];
    final end = _end;
    final days = end == null ? 1 : end.difference(_start).inDays + 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Chagua siku au kipindi'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in presets)
              Pressable(
                onTap: () => _preset(p.$2, p.$3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(20)),
                  child: Text(p.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          _calendar(),
          const SizedBox(height: 12),
          Text(
            end == null
                ? tr('Umechagua :a. Gusa siku ya mwisho, au Onyesha kwa siku hii moja.', {'a': swahiliDate(_start)})
                : end == _start
                    ? swahiliDate(_start)
                    : tr(':a – :b · siku :n', {'a': '${_start.day} ${monthNames[_start.month - 1]}', 'b': '${end.day} ${monthNames[end.month - 1]}', 'n': '$days'}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _deep, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.of(context).pop(DateTimeRange(start: _start, end: end ?? _start)),
            child: Text(tr('Onyesha'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _calendar() {
    final m = _month;
    final firstDay = DateTime(m.year, m.month);
    final lead = firstDay.weekday - 1; // Monday first
    final count = DateTime(m.year, m.month + 1, 0).day;
    final canBack = DateTime(m.year, m.month).isAfter(DateTime(widget.first.year, widget.first.month));
    final canNext = DateTime(m.year, m.month).isBefore(DateTime(widget.last.year, widget.last.month));
    final end = _end;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(22)),
      child: Column(children: [
        Row(children: [
          IconButton(
            onPressed: canBack ? () => setState(() => _month = DateTime(m.year, m.month - 1)) : null,
            icon: Icon(Icons.arrow_back_rounded, color: canBack ? Colors.white : Colors.white24),
          ),
          Expanded(
            child: Text('${monthNames[m.month - 1]} ${m.year}',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          IconButton(
            onPressed: canNext ? () => setState(() => _month = DateTime(m.year, m.month + 1)) : null,
            icon: Icon(Icons.arrow_forward_rounded, color: canNext ? Colors.white : Colors.white24),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          for (final w in weekdayShort)
            Expanded(child: Text(w, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, box) {
          final cell = box.maxWidth / 7;
          final h = cell.clamp(34.0, 44.0);
          return Wrap(children: [
            for (var i = 0; i < lead; i++) SizedBox(width: cell, height: h),
            for (var d = 1; d <= count; d++)
              () {
                final day = DateTime(m.year, m.month, d);
                final off = day.isAfter(widget.last) || day.isBefore(widget.first);
                final isStart = day == _start;
                final isEnd = end != null && day == end;
                final inside = end != null && day.isAfter(_start) && day.isBefore(end);
                final edge = isStart || isEnd;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: off ? null : () => _tap(day),
                  child: SizedBox(
                    width: cell,
                    height: h,
                    child: Stack(alignment: Alignment.center, children: [
                      // The band between the two ends.
                      if (inside || (edge && end != null && end != _start))
                        Positioned.fill(
                          left: isStart ? cell / 2 : 0,
                          right: isEnd ? cell / 2 : 0,
                          top: 4,
                          bottom: 4,
                          child: Container(color: _mint.withValues(alpha: .22)),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: h - 6,
                        height: h - 6,
                        decoration: BoxDecoration(color: edge ? _mint : Colors.transparent, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text('$d',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: edge ? FontWeight.w800 : FontWeight.w500,
                              color: off ? Colors.white24 : (edge ? _ink : Colors.white),
                            )),
                      ),
                    ]),
                  ),
                );
              }(),
          ]);
        }),
      ]),
    );
  }
}
