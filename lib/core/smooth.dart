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
