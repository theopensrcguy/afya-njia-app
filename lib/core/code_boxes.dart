import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smooth.dart';

/// Digits shown one per box (v0.48.4): the SMS code (6) or a PIN (4).
/// One hidden text field does the typing, so paste, the iPhone's "from
/// Messages" code suggestion and delete all work; the boxes only draw it.
/// [onDone] fires when the last box is filled.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.obscure = false,
    this.autofocus = false,
    this.focusNode,
    this.error = false,
    this.ok = false,
    this.onChanged,
    this.onDone,
    this.oneTimeCode = false,
  });

  final TextEditingController controller;
  final int length;
  final bool obscure;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool error;
  final bool ok;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onDone;
  final bool oneTimeCode;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_redraw);
    widget.controller.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_redraw);
    widget.controller.removeListener(_redraw);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final n = widget.length;
    final edge = widget.error ? const Color(0xFFE29A8C) : (widget.ok ? const Color(0xFF8FD0B4) : const Color(0xFF8FD0B4));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        // The real field: invisible, but it holds the text and the keyboard.
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: 56,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: widget.oneTimeCode ? const [AutofillHints.oneTimeCode] : null,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(n)],
              showCursor: false,
              enableInteractiveSelection: false,
              onChanged: (v) {
                widget.onChanged?.call(v);
                if (v.length == n) widget.onDone?.call(v);
              },
            ),
          ),
        ),
        IgnorePointer(
          child: Row(children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: n > 4 ? 8 : 12),
              Expanded(child: _box(i, text, edge)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _box(int i, String text, Color edge) {
    final filled = i < text.length;
    final current = _focus.hasFocus && (i == text.length || (i == widget.length - 1 && text.length == widget.length));
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.curve,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.error ? const Color(0xFFFDF3F1) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.error ? edge : (current ? edge : (widget.ok && filled ? edge : const Color(0xFFE3EBE7))),
          width: current || widget.error ? 1.6 : 1,
        ),
      ),
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.fast),
        transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
        child: !filled
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : widget.obscure
                ? Container(key: ValueKey('dot$i'), width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF14211D), shape: BoxShape.circle))
                : Text(text[i], key: ValueKey('d$i${text[i]}'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF14211D))),
      ),
    );
  }
}

/// A picture for a step: a soft mint circle, a big icon, and a small badge.
class StepPicture extends StatelessWidget {
  const StepPicture({super.key, required this.icon, this.badge, this.badgeColor = const Color(0xFF2F8A6C), this.size = 112});

  final IconData icon;
  final IconData? badge;
  final Color badgeColor;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .85, end: 1),
        duration: Motion.of(context, const Duration(milliseconds: 520)),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
            Container(
              decoration: const BoxDecoration(color: Color(0xFFE3F4EC), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Container(
                width: size * .62,
                height: size * .62,
                decoration: const BoxDecoration(color: Color(0xFFCFEBDD), shape: BoxShape.circle),
                child: Icon(icon, size: size * .34, color: const Color(0xFF0E3B31)),
              ),
            ),
            if (badge != null)
              Positioned(
                right: size * .1,
                bottom: size * .1,
                child: Container(
                  width: size * .28,
                  height: size * .28,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3F4EC), width: 3)),
                  child: Icon(badge, size: size * .17, color: badgeColor),
                ),
              ),
          ]),
        ),
      );
}
