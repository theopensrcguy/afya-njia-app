import 'package:flutter/material.dart';

import 'format.dart';
import 'i18n.dart';
import 'smooth.dart';

/// Pick a month and year in two taps: the year with arrows, then the 12
/// months as a grid. Used for EXP ("06/2028": the box prints month and
/// year, never a day). Months before [from] are greyed out. Returns
/// (year, month), or null when closed.
Future<(int, int)?> pickMonthYear(
  BuildContext context, {
  (int, int)? initial,
  (int, int)? from,
  int years = 12,
  String? title,
}) {
  final now = DateTime.now();
  final start = from ?? (now.year, now.month);
  return showModalBottomSheet<(int, int)>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheet) {
      var year = initial?.$1 ?? (now.year + 1);
      return StatefulBuilder(
        builder: (context, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF5B6F69))),
                ),
              Row(children: [
                IconButton(
                  onPressed: year > start.$1 ? () => set(() => year--) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.fast),
                    child: Text('$year',
                        key: ValueKey(year), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
                IconButton(
                  onPressed: year < start.$1 + years ? () => set(() => year++) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, box) {
                final w = (box.maxWidth - 3 * 8) / 4;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var m = 1; m <= 12; m++)
                    Builder(builder: (_) {
                      final before = year < start.$1 || (year == start.$1 && m < start.$2);
                      final on = initial != null && initial.$1 == year && initial.$2 == m;
                      final name = monthNames[m - 1];
                      return SizedBox(
                        width: w,
                        height: 52,
                        child: Material(
                          color: on ? const Color(0xFF12644E) : (before ? const Color(0xFFF5F8F7) : const Color(0xFFEEF3F1)),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: before
                                ? null
                                : () {
                                    tick();
                                    Navigator.of(sheet).pop((year, m));
                                  },
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(name.length > 3 ? name.substring(0, 3) : name,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: on ? Colors.white : (before ? const Color(0xFFB8C4C0) : const Color(0xFF14211D)))),
                              Text(m.toString().padLeft(2, '0'),
                                  style: TextStyle(fontSize: 11, color: on ? Colors.white70 : const Color(0xFF5B6F69))),
                            ]),
                          ),
                        ),
                      );
                    }),
                ]);
              }),
              const SizedBox(height: 8),
              Text(tr('Kama kwenye boksi: EXP 06/2028 = mwisho wa Juni 2028.'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF5B6F69))),
            ]),
          ),
        ),
      );
    },
  );
}
