import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

/// How the app should FEEL, in one place (v0.44). The pains this answers,
/// common in many apps:
///
///  1. A spinner every time you open a screen you saw a minute ago.
///     → [ApiCache]: the last answer shows at once, the fresh one replaces it
///       quietly (the thin bar at the top says it's checking).
///  2. The screen going blank while a filter loads, then jumping.
///     → keep the old results, dimmed, until the new ones arrive.
///  3. Losing your filter, sort or view every time you come back.
///     → [UiMemory].
///  4. Taps that feel dead. → [Pressable] (a small press + a light tick).
///  5. Motion that makes some people feel sick. → [Motion.of] turns it off
///     when the phone's "Reduce Motion" setting is on.
///  6. A grey spinner on first load. → [Skeleton]: the shape of what's coming.

/// The last answer per request, for this session and shop. The key includes
/// the token, so another person or another shop never sees these answers.
class ApiCache {
  static final _store = <String, dynamic>{};

  static String _key(ApiClient api, String path, Map<String, String>? q) =>
      '${api.token}|$path|${q == null ? '' : (q.keys.toList()..sort()).map((k) => '$k=${q[k]}').join('&')}';

  /// What we had last time (null if never).
  static dynamic peek(ApiClient api, String path, {Map<String, String>? query}) => _store[_key(api, path, query)];

  /// Ask the server and remember the answer.
  static Future<dynamic> fetch(ApiClient api, String path, {Map<String, String>? query}) async {
    final data = await api.get(path, query: query);
    _store[_key(api, path, query)] = data;
    return data;
  }

  static void clear() => _store.clear();
}

/// Choices a person made on a screen (filter, sort, view), kept while the app
/// is open, so coming back finds the screen as they left it.
class UiMemory {
  static final _m = <String, Object?>{};
  static T get<T>(String key, T fallback) => (_m[key] as T?) ?? fallback;
  static void set(String key, Object? value) => _m[key] = value;
}

class Motion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 650);
  static const curve = Curves.easeOutCubic;

  /// [d], or no animation when the phone asks for less motion.
  static Duration of(BuildContext context, Duration d) => MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// A light tick on choices (chips, switches, tabs). Not on every tap: too much
/// vibration becomes noise.
void tick() => HapticFeedback.selectionClick();

/// Anything tappable that should feel physical: shrinks a little while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.haptic = false, this.borderRadius});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) tick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Motion.of(context, const Duration(milliseconds: 110)),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A grey block in the shape of what will appear, breathing gently.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0xFFE3EAE7), const Color(0xFFEEF3F1), still ? 0.5 : _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Two to four choices with a thumb that slides to the chosen one.
class SlidingSegments<T> extends StatelessWidget {
  const SlidingSegments({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
    this.height = 40,
    this.background = const Color(0xFFE3EAE7),
    this.fontSize = 14,
  });

  final List<T> values;
  final List<String> labels;
  final List<IconData>? icons;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final Color background;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final i = values.indexOf(selected).clamp(0, values.length - 1);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(height / 2.6)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / values.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            left: w * i,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular((height - 6) / 2.6),
                boxShadow: const [BoxShadow(color: Color(0x1A14211D), blurRadius: 4, offset: Offset(0, 1))],
              ),
            ),
          ),
          Row(children: [
            for (var k = 0; k < values.length; k++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: k == i,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (k == i) return;
                      tick();
                      onChanged(values[k]);
                    },
                    child: Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icons != null) ...[
                          Icon(icons![k], size: fontSize + 2, color: k == i ? const Color(0xFF14211D) : const Color(0xFF44564F)),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.of(context, Motion.fast),
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: k == i ? FontWeight.w700 : FontWeight.w600,
                              color: k == i ? const Color(0xFF14211D) : const Color(0xFF44564F),
                            ),
                            child: Text(labels[k], maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// A filter chip: dark when chosen, with an optional colour dot and count.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({super.key, required this.label, required this.selected, required this.onTap, this.dot, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFF14211D);
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: () {
          tick();
          onTap();
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.curve,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF14211D) : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? const Color(0xFF14211D) : const Color(0xFFDCE5E1), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(color: fg.withValues(alpha: .7), fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A filter that always fits: half the row, its name small and its value big,
/// dark when it narrows the list. Opens [pickOne]. Replaces chip rows that ran
/// off the screen's edge.
class DropPill extends StatelessWidget {
  const DropPill({super.key, required this.label, required this.value, required this.active, required this.onTap, this.dot});

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : const Color(0xFF14211D);
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          height: 46,
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF14211D) : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? const Color(0xFF14211D) : const Color(0xFFDCE5E1), width: 1.5),
          ),
          child: Row(children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: .65))),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
              ]),
            ),
            Icon(Icons.expand_more_rounded, size: 20, color: fg.withValues(alpha: .8)),
          ]),
        ),
      ),
    );
  }
}

/// One choice in [pickOne]'s sheet.
class PickOption<T> {
  const PickOption(this.value, this.label, {this.count, this.dot, this.sub});
  final T value;
  final String label;
  final int? count;
  final Color? dot;
  final String? sub;
}

/// A sheet of choices with counts; the chosen one ticked. Tall lists scroll.
Future<T?> pickOne<T>(BuildContext context, {required String title, required List<PickOption<T>> options, required T selected}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * .75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF14211D))),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
              for (final o in options)
                ListTile(
                  minTileHeight: 52,
                  leading: o.dot == null
                      ? null
                      : Container(width: 12, height: 12, decoration: BoxDecoration(color: o.dot, borderRadius: BorderRadius.circular(4))),
                  title: Text(o.label, style: TextStyle(fontWeight: o.value == selected ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: o.sub == null ? null : Text(o.sub!),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (o.count != null) Text('${o.count}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF5B6F69))),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 22,
                      child: o.value == selected ? const Icon(Icons.check_rounded, color: Color(0xFF12644E)) : null,
                    ),
                  ]),
                  onTap: () {
                    tick();
                    Navigator.of(sheet).pop(o.value);
                  },
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
