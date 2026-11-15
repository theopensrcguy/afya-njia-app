import 'package:flutter/material.dart';

import 'api_client.dart';
import 'brand.dart';
import 'i18n.dart';

/// The Afya Njia loader: the green "A" mark breathing inside a turning ring.
/// Used wherever a screen waits for the server, so waiting looks the same
/// everywhere (and clearly "working", not stuck).
class AfyaLoader extends StatefulWidget {
  const AfyaLoader({super.key, this.size = 56, this.label});

  final double size;

  /// Optional words under the mark ("Inashughulikia…").
  final String? label;

  @override
  State<AfyaLoader> createState() => _AfyaLoaderState();
}

class _AfyaLoaderState extends State<AfyaLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: s,
            height: s,
            child: CircularProgressIndicator(strokeWidth: s / 18, color: brandGreen, backgroundColor: mintSoft, strokeCap: StrokeCap.round),
          ),
          ScaleTransition(
            scale: Tween(begin: 0.86, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              width: s * 0.58,
              height: s * 0.58,
              decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(s * 0.17)),
              alignment: Alignment.center,
              child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: s * 0.3)),
            ),
          ),
        ]),
      ),
      if (widget.label != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(widget.label!, style: const TextStyle(fontWeight: FontWeight.w700, color: inkColor)),
        ),
    ]);
  }
}

/// Over every screen (MaterialApp.builder): a thin green bar at the top while
/// anything is loading, and, when a save takes more than about a second, the
/// Afya Njia loader in the middle (taps wait; the request can't be sent twice).
class ActivityLayer extends StatefulWidget {
  const ActivityLayer({super.key, required this.child});

  final Widget child;

  @override
  State<ActivityLayer> createState() => _ActivityLayerState();
}

class _ActivityLayerState extends State<ActivityLayer> {
  bool _bar = false;
  bool _overlay = false;
  int _barTicket = 0;
  int _overlayTicket = 0;

  @override
  void initState() {
    super.initState();
    apiActivity.addListener(_onActivity);
    apiSaving.addListener(_onSaving);
  }

  @override
  void dispose() {
    apiActivity.removeListener(_onActivity);
    apiSaving.removeListener(_onSaving);
    super.dispose();
  }

  // A short delay before showing anything: quick answers don't flicker.
  void _onActivity() {
    final ticket = ++_barTicket;
    if (apiActivity.value == 0) {
      if (_bar) setState(() => _bar = false);
      return;
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && ticket == _barTicket && apiActivity.value > 0 && !_bar) setState(() => _bar = true);
    });
  }

  void _onSaving() {
    final ticket = ++_overlayTicket;
    if (apiSaving.value == 0) {
      if (_overlay) setState(() => _overlay = false);
      return;
    }
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && ticket == _overlayTicket && apiSaving.value > 0 && !_overlay) setState(() => _overlay = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_overlay)
        Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: 0.18),
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22), boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12)),
                ]),
                child: AfyaLoader(label: tr('Inashughulikia…')),
              ),
            ),
          ),
        ),
      if (_bar)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: LinearProgressIndicator(minHeight: 3, color: brandGreen, backgroundColor: mintSoft.withValues(alpha: 0.6)),
          ),
        ),
    ]);
  }
}
