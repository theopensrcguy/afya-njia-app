import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/money.dart';
import '../../../core/session.dart';
import '../../../core/smooth.dart';
import '../../stock/stock_look.dart';

const _ink = Color(0xFF14211D);
const _muted = Color(0xFF5B6F69);
const _primary = Color(0xFF12644E);

/// Hali ya hisa on the owner's home (v0.44): the same numbers as the web's
/// Muhtasari (GET stock/insight).
///
///  - a ring of the five states; tap a piece (or its line) to focus it, and
///    the button opens the stock list on exactly that;
///  - four money tiles (hidden with the home's eye, like every amount there);
///  - what sells most (Leo / Wiki / Mwezi) with how many days it will last;
///  - the latest stock events.
///
/// Shows the last answer at once and refreshes quietly (ApiCache).
class StockInsightCard extends StatefulWidget {
  const StockInsightCard({super.key, required this.session, required this.hidden, required this.refreshTick, required this.onOpenStock});

  final Session session;
  final bool hidden;
  final int refreshTick;
  final void Function(String filter) onOpenStock;

  @override
  State<StockInsightCard> createState() => _StockInsightCardState();
}

class _StockInsightCardState extends State<StockInsightCard> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _focus; // a state key
  String _period = UiMemory.get('home.movers', 'wiki');

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    final c = ApiCache.peek(_api, 'stock/insight');
    if (c is Map<String, dynamic>) _data = c;
    _load();
  }

  @override
  void didUpdateWidget(StockInsightCard old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiCache.fetch(_api, 'stock/insight') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        // The week empty (a Monday morning)? Open on the month.
        final movers = (d['movers'] as Map?) ?? const {};
        if (UiMemory.get<String?>('home.movers', null) == null && ((movers['wiki'] as List?) ?? const []).isEmpty) _period = 'mwezi';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _money(int v) {
    if (widget.hidden) return tr('TSh ••••••');
    if (v.abs() >= 1000000) return 'TSh ${(v / 1000000).toStringAsFixed(2)}M';
    return formatTsh(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: T('Hali ya hisa', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -0.2)),
      ),
      AnimatedSwitcher(
        duration: Motion.of(context, Motion.base),
        child: d == null
            ? (_error != null ? _errorBox() : const _InsightSkeleton())
            : Column(key: const ValueKey('data'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _health(d),
                if (d['money'] is Map) ...[const SizedBox(height: 10), _moneyTiles(d['money'] as Map)],
                const SizedBox(height: 12),
                _movers(d),
                if (((d['activity'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 12), _activity(d['activity'] as List)],
              ]),
      ),
    ]);
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: child,
      );

  Widget _errorBox() => _card(
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: _muted),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: const TextStyle(color: _ink))),
          TextButton(onPressed: _load, child: const T('Jaribu tena')),
        ]),
      );

  // ------------------------------------------------------------ the ring

  static const _filterFor = {'expired': 'zimeisha', 'out': 'hazipo', 'low': 'chache', 'expiring': 'muda', 'ok': 'zote'};
  static const _ringOrder = ['ok', 'expiring', 'low', 'out', 'expired'];

  Widget _health(Map<String, dynamic> d) {
    final h = (d['health'] as Map?) ?? const {};
    final states = (h['states'] as Map?) ?? const {};
    final total = asInt(h['products']);
    final segs = [
      for (final k in _ringOrder) (k, asInt((states[k] as Map?)?['count'])),
    ];
    final focus = _focus;
    final sel = focus == null ? null : segs.firstWhere((s) => s.$1 == focus);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 136,
            height: 136,
            child: GestureDetector(
              onTapUp: (e) {
                final i = _Ring.hit(e.localPosition, const Size(136, 136), segs.map((s) => s.$2).toList());
                if (i != null) _toggle(segs[i].$1);
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, Motion.slow * 1.4),
                curve: Motion.curve,
                builder: (_, t, _) => CustomPaint(
                  painter: _Ring(
                    values: segs.map((s) => s.$2).toList(),
                    colors: segs.map((s) => stateLooks[s.$1]!.color).toList(),
                    focus: focus == null ? null : _ringOrder.indexOf(focus),
                    progress: t,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      child: Column(
                        key: ValueKey(focus),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${sel?.$2 ?? total}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _ink)),
                          SizedBox(
                            width: 80,
                            child: Text(sel == null ? tr('bidhaa zote') : tr(stateLooks[sel.$1]!.label),
                                textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, height: 1.2, color: _muted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              for (final s in segs)
                Semantics(
                  button: true,
                  selected: focus == s.$1,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggle(s.$1),
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(color: focus == s.$1 ? const Color(0xFFF2F6F4) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                      child: AnimatedOpacity(
                        duration: Motion.of(context, Motion.fast),
                        opacity: focus != null && focus != s.$1 ? .45 : 1,
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: stateLooks[s.$1]!.color, borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(tr(stateLooks[s.$1]!.label), style: const TextStyle(fontSize: 13, color: _ink))),
                          Text('${s.$2}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Pressable(
          onTap: () => widget.onOpenStock(_filterFor[focus] ?? 'zote'),
          child: Container(
            height: 46,
            decoration: BoxDecoration(color: const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(13)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  child: Text(
                    focus == null || focus == 'ok' ? tr('Fungua orodha ya hisa') : tr('Fungua orodha: :a', {'a': tr(stateLooks[focus]!.label)}),
                    key: ValueKey(focus),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: _primary),
            ]),
          ),
        ),
      ]),
    );
  }

  void _toggle(String k) {
    tick();
    setState(() => _focus = _focus == k ? null : k);
  }

  // ------------------------------------------------------------ money

  Widget _moneyTiles(Map m) {
    Widget tile(String label, String value, {Color bg = Colors.white, Color fg = _ink, Color sub = _muted}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: sub)),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: FittedBox(
                  key: ValueKey('$value${widget.hidden}'),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                ),
              ),
            ]),
          ),
        );
    final margin = m['margin'];
    return Column(children: [
      Row(children: [
        tile(tr('Thamani (bei ya kununua)'), _money(asInt(m['cost']))),
        const SizedBox(width: 10),
        tile(tr('Thamani (bei ya kuuza)'), _money(asInt(m['price']))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(tr('Faida iliyomo'), '${_money(asInt(m['profit']))}${margin == null || widget.hidden ? '' : ' · $margin%'}',
            bg: const Color(0xFFE7F6EF), fg: const Color(0xFF0E5A44), sub: const Color(0xFF2D5B4D)),
        const SizedBox(width: 10),
        tile(tr('Hatarini (muda)'), _money(asInt(m['at_risk'])), bg: const Color(0xFFFDF1E3), fg: const Color(0xFF7A4A12), sub: const Color(0xFF7A4A12)),
      ]),
    ]);
  }

  // ------------------------------------------------------------ movers

  Widget _movers(Map<String, dynamic> d) {
    final lists = (d['movers'] as Map?) ?? const {};
    final rows = ((lists[_period] as List?) ?? const []).cast<Map<String, dynamic>>();
    return _card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: T('Zinazosonga zaidi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink))),
          SizedBox(
            width: 168,
            child: SlidingSegments<String>(
              values: const ['leo', 'wiki', 'mwezi'],
              labels: [tr('Leo'), tr('Wiki'), tr('Mwezi')],
              selected: _period,
              height: 34,
              fontSize: 12.5,
              background: const Color(0xFFF2F6F4),
              onChanged: (v) {
                setState(() => _period = v);
                UiMemory.set('home.movers', v);
              },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.base),
          child: Column(
            key: ValueKey(_period),
            children: rows.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: T(_period == 'leo' ? 'Bado hakuna mauzo leo.' : 'Hakuna mauzo kipindi hiki.', style: const TextStyle(color: _muted)),
                    ),
                  ]
                : [
                    for (var i = 0; i < rows.length; i++) _moverRow(i + 1, rows[i]),
                  ],
          ),
        ),
        if (rows.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4),
            child: T('Siku = itakavyodumu kwa kasi ya siku 30 zilizopita.', style: TextStyle(fontSize: 12, color: _muted)),
          ),
      ]),
    );
  }

  Widget _moverRow(int rank, Map<String, dynamic> m) {
    final days = m['days'];
    final (bg, fg) = switch ('${m['cover']}') {
      'out' || 'short' => (const Color(0xFFFBE9E5), const Color(0xFFA8321F)),
      'mid' => (const Color(0xFFFDF1E3), const Color(0xFF7A4A12)),
      _ => (const Color(0xFFE7F6EF), const Color(0xFF0E5A44)),
    };
    final badge = '${m['cover']}' == 'out' ? tr('Imeisha') : (days == null ? '—' : tr('siku :n', {'n': days}));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
      child: Row(children: [
        SizedBox(width: 22, child: Text('$rank', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8A9B95)))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 2),
            Text(tr(':a zimeuzwa · zimebaki :b', {'a': m['sold_text'], 'b': m['left_text']}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ activity

  Widget _activity(List items) {
    const looks = {
      'in': (Icons.local_shipping_outlined, Color(0xFFE7F6EF), Color(0xFF12644E)),
      'count': (Icons.fact_check_outlined, Color(0xFFEAF0FD), Color(0xFF2F5FC4)),
      'fix': (Icons.tune_rounded, Color(0xFFFDF1E3), Color(0xFF7A4A12)),
      'out': (Icons.delete_outline_rounded, Color(0xFFFBE9E5), Color(0xFFB5371F)),
      'move': (Icons.swap_horiz_rounded, Color(0xFFF0ECF7), Color(0xFF5B4790)),
    };
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const T('Shughuli za hisa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 8),
        for (final a in items.cast<Map<String, dynamic>>().take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Builder(builder: (_) {
                final (icon, bg, fg) = looks['${a['kind']}'] ?? looks['move']!;
                return Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 18, color: fg),
                );
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['title']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                  const SizedBox(height: 2),
                  Text([a['sub'], a['by'], a['ago']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// The ring: flat-ended pieces with clear gaps (like the web), each at least 3%
/// so a tiny share still shows; the focused piece is thicker, the others fade.
class _Ring extends CustomPainter {
  _Ring({required this.values, required this.colors, required this.focus, required this.progress});
  final List<int> values;
  final List<Color> colors;
  final int? focus;
  final double progress;

  static const _gap = 0.07; // radians
  static const _stroke = 15.0;

  static List<(double, double)> _arcs(List<int> values) {
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return [];
    final shares = values.map((v) => v == 0 ? 0.0 : math.max(v / total, .03)).toList();
    final sum = shares.fold<double>(0, (a, b) => a + b);
    var start = -math.pi / 2;
    final out = <(double, double)>[];
    for (final s in shares) {
      final sweep = s / sum * 2 * math.pi;
      out.add((start, sweep));
      start += sweep;
    }
    return out;
  }

  /// Which piece a tap landed on (null: the middle or outside).
  static int? hit(Offset p, Size size, List<int> values) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - _stroke - 6) / 2;
    final dist = (p - c).distance;
    if (dist < r - 22 || dist > r + 22) return null;
    var a = math.atan2(p.dy - c.dy, p.dx - c.dx);
    if (a < -math.pi / 2) a += 2 * math.pi;
    final arcs = _arcs(values);
    for (var i = 0; i < arcs.length; i++) {
      final (s, w) = arcs[i];
      if (w > 0 && a >= s && a <= s + w) return i;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - _stroke - 6) / 2;
    final arcs = _arcs(values);
    if (arcs.isEmpty) {
      canvas.drawCircle(c, r, Paint()
        ..color = const Color(0xFFEEF3F1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke);
      return;
    }
    final limit = -math.pi / 2 + 2 * math.pi * progress;
    for (var i = 0; i < arcs.length; i++) {
      var (start, sweep) = arcs[i];
      if (sweep <= 0 || start >= limit) continue;
      sweep = math.min(sweep, limit - start) - _gap;
      if (sweep <= 0) continue;
      final on = focus == i;
      final paint = Paint()
        ..color = colors[i].withValues(alpha: focus != null && !on ? .25 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? _stroke + 5 : _stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start + _gap / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_Ring o) => o.progress != progress || o.focus != focus || o.values != values;
}

class _InsightSkeleton extends StatelessWidget {
  const _InsightSkeleton();

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            const Skeleton(width: 132, height: 132, radius: 66),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [for (var i = 0; i < 5; i++) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Skeleton(height: 12))])),
          ]),
        ),
        const SizedBox(height: 10),
        const Row(children: [Expanded(child: Skeleton(height: 70, radius: 18)), SizedBox(width: 10), Expanded(child: Skeleton(height: 70, radius: 18))]),
      ]);
}
