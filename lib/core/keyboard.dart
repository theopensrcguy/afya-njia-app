import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The keyboard goes away when it should (v0.46.1).
///
/// Two leaks, two fixes:
///  * A tap anywhere that is not a text box closes it. The old way (a
///    GestureDetector around the app) lost the tap to any button, list row or
///    sheet under the finger, so the keyboard often stayed. This listens to
///    the raw finger instead: a short touch that lands outside every text box
///    closes the keyboard, whatever else the tap does.
///  * Coming back to a screen: Flutter gives focus back to the box that had
///    it before you left, so the keyboard popped up on screens you only
///    returned to. [KeyboardObserver] drops that focus after every pop.
class KeyboardDismisser extends StatefulWidget {
  const KeyboardDismisser({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardDismisser> createState() => _KeyboardDismisserState();
}

class _KeyboardDismisserState extends State<KeyboardDismisser> {
  Offset? _down;
  DateTime? _at;

  void _up(PointerUpEvent e) {
    final down = _down, at = _at;
    _down = null;
    if (down == null || at == null) return;
    // A scroll or a long press is not "tap away".
    if ((e.position - down).distance > 12 || DateTime.now().difference(at).inMilliseconds > 500) return;
    if (FocusManager.instance.primaryFocus == null) return;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, e.position, View.of(context).viewId);
    // The whole text box counts (its padding, its icons), not just the
    // letters: TextField marks itself with a TapRegion of group EditableText.
    final onText = result.path.any((h) {
      final t = h.target;
      return t is RenderEditable || (t is RenderTapRegion && t.groupId == EditableText);
    });
    if (!onText) hideKeyboard();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _down = e.position;
          _at = DateTime.now();
        },
        onPointerUp: _up,
        onPointerCancel: (_) => _down = null,
        child: widget.child,
      );
}

/// Close the keyboard now: drop the focus and tell the phone to hide it
/// (iOS sometimes kept the keys on screen after the focus was gone).
void hideKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// Every screen change: leaving a screen closes its keyboard; coming back to
/// one doesn't reopen it (the focus Flutter restores is dropped after the
/// frame). A pushed screen that wants its keyboard (autofocus) still gets it.
class KeyboardObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _afterFrame();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _afterFrame();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => FocusManager.instance.primaryFocus?.unfocus();

  void _afterFrame() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => hideKeyboard());
  }
}

final keyboardObserver = KeyboardObserver();
