import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/money.dart';
import '../../../core/session.dart';
import '../../../core/smooth.dart';
import '../../insights/insight_parts.dart';
import '../../stock/stock_look.dart';

/// The owner's home below the header (v0.45, canvas screen 5): one period
/// switch (Leo / Wiki / Mwezi) drives everything; each number says how it
/// moved against the same stretch before. GET insights/home (+ stock/insight
/// for the one-line stock health).
class OwnerHome extends StatefulWidget {
  const OwnerHome({
    super.key,
    required this.session,
    required this.hidden,
    required this.onToggleHidden,
    required this.refreshTick,
    required this.actions,
    required this.onOpenStock,
    required this.onTip,
    this.onSetTarget,
    this.showStock = true,
    this.lead,
  });

  final Session session;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final int refreshTick;

  /// Quick actions (Uza, Pokea, Agiza, Skani…), already filtered by permission.
  final List<({IconData icon, String label, VoidCallback onTap, bool primary})> actions;
  final void Function(String filter) onOpenStock;
  final void Function(Map<String, dynamic> tip) onTip;
  final VoidCallback? onSetTarget;

  /// Hali ya hisa (needs the stock permission).
  final bool showStock;

  /// Sits left of the period switch (the shop pill), as on the canvas.
  final Widget? lead;

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  String _period = UiMemory.get('home.period', 'leo');
  int? _day; // the week bar tapped

  ApiClient get _api => widget.session.api;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _periodRow(),
      const SizedBox(height: 12),
      CachedJson(
        api: _api,
        path: 'insights/home',
        query: {'period': _period},
        refreshTick: widget.refreshTick,
        skeleton: const Column(children: [CardSkeleton(height: 200), SizedBox(height: 12), CardSkeleton(height: 140)]),
        builder: (context, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Appear(child: _hero(d)),
          const SizedBox(height: 16),
          Appear(index: 1, child: _actions()),
          if (d['tip'] is Map) ...[const SizedBox(height: 16), Appear(index: 2, child: _tip(d['tip'] as Map<String, dynamic>))],
          const SizedBox(height: 14),
          Appear(index: 3, child: _kpis(d)),
          const SizedBox(height: 14),
          Appear(index: 4, child: _week(d)),
          const SizedBox(height: 14),
          Appear(index: 5, child: _busy(d)),
          if (((d['top'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), Appear(index: 6, child: _top(d))],
        ]),
      ),
      if (widget.showStock) ...[const SizedBox(height: 14), Appear(index: 7, child: _stockRow())],
    ]);
  }

  /// Shop pill and a compact Leo / Wiki / Mwezi on one row; without a shop
  /// name the switch takes the whole width with the longer labels.
  Widget _periodRow() {
    void pick(String v) {
      setState(() => (_period = v, _day = null));
      UiMemory.set('home.period', v);
    }

    final lead = widget.lead;
    if (lead == null) {
      return SlidingSegments<String>(
        values: const ['leo', 'wiki', 'mwezi'],
        labels: [tr('Leo'), tr('Wiki hii'), tr('Mwezi huu')],
        selected: _period,
        height: 40,
        fontSize: 13,
        onChanged: pick,
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(204.0, box.maxWidth * .6);
      return Row(children: [
        Expanded(child: lead),
        const SizedBox(width: 8),
        SizedBox(
          width: w,
          child: SlidingSegments<String>(
            values: const ['leo', 'wiki', 'mwezi'],
            labels: [tr('Leo'), tr('Wiki'), tr('Mwezi')],
            selected: _period,
            height: 40,
            fontSize: 13,
            onChanged: pick,
          ),
        ),
      ]);
    });
  }

  String get _than => switch (_period) {
        'wiki' => tr('kuliko wiki iliyopita'),
        'mwezi' => tr('kuliko mwezi uliopita'),
        _ => tr('kuliko jana'),
      };

  String _m(int v) => tshShort(v, hidden: widget.hidden);

  // ------------------------------------------------------------ hero

  Widget _hero(Map<String, dynamic> d) {
    final s = (d['sales'] as Map?) ?? const {};
    final pay = (s['payments'] as Map?) ?? const {};
    final parts = [
      ('cash', tr('Taslimu'), kMint),
      ('mobile', tr('Simu'), const Color(0xFF8FB2FF)),
      ('insurance', tr('Bima'), const Color(0xFFF2C46B)),
      if (asInt(pay['credit']) > 0) ('credit', tr('Deni'), const Color(0xFFF9B4A6)),
    ];
    final total = parts.fold<int>(0, (a, p) => a + asInt(pay[p.$1]));
    final title = switch (_period) { 'wiki' => tr('Mauzo ya wiki hii'), 'mwezi' => tr('Mauzo ya mwezi huu'), _ => tr('Mauzo ya leo') };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFFB7D3C9))),
                const SizedBox(width: 2),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: widget.hidden ? tr('Onyesha kiasi') : tr('Ficha kiasi'),
                  onPressed: widget.onToggleHidden,
                  icon: Icon(widget.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFFB7D3C9)),
                ),
              ]),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: widget.hidden
                    ? T('TSh ••••••', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5))
                    : CountUp(
                        value: asInt(s['total']),
                        format: formatTsh,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                      ),
              ),
              const SizedBox(height: 6),
              DeltaBadge(delta: s['delta'] as num?, than: _than, onDark: true),
            ]),
          ),
          Semantics(
            button: widget.onSetTarget != null,
            label: tr('Lengo'),
            child: GestureDetector(
              onTap: widget.onSetTarget,
              child: SemiGauge(
                pct: s['target_pct'] as int?,
                label: s['target'] == null ? tr('Weka') : null,
                caption: s['target'] == null ? tr('lengo') : tr('ya lengo'),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? Container(color: Colors.white.withValues(alpha: .12))
                : Row(children: [
                    for (final p in parts)
                      if (asInt(pay[p.$1]) > 0) Expanded(flex: math.max(1, asInt(pay[p.$1]) * 1000 ~/ total), child: Container(margin: const EdgeInsets.only(right: 2), color: p.$3)),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (final p in parts)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(p.$2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFFB7D3C9)))),
                ]),
                const SizedBox(height: 2),
                Text(widget.hidden ? '•••' : shortMoney(asInt(pay[p.$1])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------ actions, tip

  /// v0.46.1: selling is the point of the app, so Uza is no longer one circle
  /// among four: a wide green button with a slow glow, the first thing the eye
  /// lands on. The other actions stay as small circles beside it.
  Widget _actions() {
    final list = widget.actions.take(4).toList();
    final primary = list.where((a) => a.primary).firstOrNull;
    final rest = list.where((a) => a != primary).take(3).toList();
    Widget circle(({IconData icon, String label, VoidCallback onTap, bool primary}) a) => Expanded(
          child: Semantics(
            button: true,
            label: a.label,
            excludeSemantics: true,
            child: Pressable(
              onTap: a.onTap,
              child: Column(children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(a.icon, color: kInk, size: 21),
                ),
                const SizedBox(height: 6),
                Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kInk)),
              ]),
            ),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (primary != null) ...[Expanded(flex: 5, child: UzaButton(label: primary.label, onTap: primary.onTap)), const SizedBox(width: 8)],
      for (final a in rest) circle(a),
    ]);
  }

  Widget _tip(Map<String, dynamic> tip) {
    final kind = '${tip['kind']}';
    final (icon, bg, fg, action) = switch (kind) {
      'reorder' => (Icons.lightbulb_outline_rounded, kBadSoft, kBad, tr('Agiza sasa')),
      'expired' => (Icons.event_busy_outlined, const Color(0xFFF0ECF7), const Color(0xFF5B4790), tr('Ona bidhaa hizo')),
      _ => (Icons.bedtime_outlined, const Color(0xFFFDF1E3), const Color(0xFF7A4A12), tr('Ona hisa')),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE3EAE7), width: 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: fg, size: 21)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T('KIDOKEZO CHA LEO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: fg)),
            const SizedBox(height: 4),
            Text('${tip['text']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: kInk)),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: kPrimary),
              onPressed: () => widget.onTip(tip),
              child: Text('$action →', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ KPIs

  Widget _kpis(Map<String, dynamic> d) {
    final k = (d['kpis'] as Map?) ?? const {};
    final tiles = <Widget>[
      if (k['profit'] is Map)
        _kpi(Icons.trending_up_rounded, kGoodSoft, kGood, _m(asInt(k['profit']['now'])), tr('Faida'), DeltaBadge(delta: k['profit']['delta'] as num?)),
      if (k['count'] is Map)
        _kpi(Icons.receipt_long_outlined, const Color(0xFFEAF0FD), const Color(0xFF2F5FC4), '${k['count']['now']}', tr('Mauzo'), DeltaBadge(delta: null, diff: k['count']['diff'] as num?)),
      if (k['average'] is Map)
        _kpi(Icons.shopping_basket_outlined, const Color(0xFFFDF1E3), const Color(0xFF7A4A12), _m(asInt(k['average']['now'])), tr('Wastani wa mauzo'),
            DeltaBadge(delta: k['average']['delta'] as num?)),
      if (k['expenses'] is Map && _period == 'mwezi')
        _kpi(Icons.payments_outlined, kBadSoft, kBad, _m(asInt(k['expenses']['now'])), tr('Matumizi'), DeltaBadge(delta: k['expenses']['delta'] as num?, upIsGood: false))
      else if (k['customers'] is Map)
        _kpi(Icons.person_add_alt_outlined, const Color(0xFFF0ECF7), const Color(0xFF5B4790), '${k['customers']['now']}', tr('Wateja wapya'),
            DeltaBadge(delta: null, diff: k['customers']['diff'] as num?)),
    ];
    return Column(children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: Row(children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
    ]);
  }

  Widget _kpi(IconData icon, Color bg, Color fg, String value, String label, Widget delta) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: fg)),
          const Spacer(),
          delta,
        ]),
        const SizedBox(height: 10),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk))),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
      ]),
    );
  }

  // ------------------------------------------------------------ week

  static const _dayShort = ['J3', 'J4', 'J5', 'Al', 'Ij', 'J1', 'J2'];

  Widget _week(Map<String, dynamic> d) {
    final week = ((d['week'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final values = List<int>.generate(7, (i) => i < week.length ? asInt(week[i]['total']) : 0);
    final max = math.max(1, values.reduce(math.max));
    final today = math.max(0, week.length - 1);
    final sel = _day ?? today;
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Mauzo ya wiki'), trailing: T('gusa siku', style: const TextStyle(fontSize: 12, color: kMuted))),
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: Text(
              key: ValueKey(sel),
              sel < week.length ? '${tr(_dayShort[sel])}: ${widget.hidden ? tr('TSh ••••••') : formatTsh(values[sel])} · ${tr('mauzo :n', {'n': week[sel]['count']})}' : '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk),
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${tr(_dayShort[i])} ${formatTsh(values[i])}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: i < week.length
                        ? () {
                            tick();
                            setState(() => _day = i);
                          }
                        : null,
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: values[i] / max),
                        duration: Motion.of(context, Duration(milliseconds: 400 + i * 50)),
                        curve: Motion.curve,
                        builder: (_, v, _) => AnimatedContainer(
                          duration: Motion.of(context, Motion.fast),
                          height: math.max(6, v * 100),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: i >= week.length ? const Color(0xFFEEF3F1) : (i == sel ? kPrimary : const Color(0xFFCDEFE0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(tr(_dayShort[i]),
                          style: TextStyle(fontSize: 11, fontWeight: i == today ? FontWeight.w700 : FontWeight.w500, color: i == today ? kPrimary : kMuted)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ busy hours

  Widget _busy(Map<String, dynamic> d) {
    final b = (d['busy'] as Map?) ?? const {};
    final hours = ((b['hours'] as List?) ?? const []).map(asInt).toList();
    final rows = ((b['rows'] as List?) ?? const []);
    const shades = [Color(0xFFF2F6F4), Color(0xFFDDF1E8), Color(0xFFB5E3CE), Color(0xFF6CC4A0), Color(0xFF1F8A66)];
    // Two-hour blocks keep the grid readable on a phone.
    final blocks = <int>[for (var h = 8; h <= 20; h += 2) h];
    int level(int day, int from) {
      if (day >= rows.length) return 0;
      final row = rows[day];
      int at(int h) {
        final i = hours.indexOf(h);
        final cell = row is Map ? row['$h'] : (row is List && i >= 0 && i < row.length ? row[i] : null);
        return cell is Map ? asInt(cell['level']) : 0;
      }

      return math.max(at(from), at(from + 1));
    }

    final peak = b['peak'] as Map?;
    const longDays = ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Saa za shughuli'), trailing: T('wiki 4 zilizopita', style: const TextStyle(fontSize: 12, color: kMuted))),
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 26),
          for (final d in _dayShort) Expanded(child: Center(child: Text(tr(d), style: const TextStyle(fontSize: 10, color: kMuted)))),
        ]),
        const SizedBox(height: 4),
        for (final h in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 26, child: Text('$h', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: kMuted))),
              const SizedBox(width: 4),
              for (var day = 0; day < 7; day++)
                Expanded(
                  child: Container(
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: shades[level(day, h)], borderRadius: BorderRadius.circular(6)),
                  ),
                ),
            ]),
          ),
        if (peak != null) ...[
          const SizedBox(height: 6),
          Text(
            tr('Kilele: :day saa :h. Weka watu wawili kaunta.', {'day': tr(longDays[asInt(peak['day']).clamp(0, 6)]), 'h': '${peak['hour']}:00'}),
            style: const TextStyle(fontSize: 12, color: kMuted),
          ),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------ top, stock

  Widget _top(Map<String, dynamic> d) {
    final top = ((d['top'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Zinazouzwa zaidi')),
        const SizedBox(height: 6),
        for (final t in top)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: kGoodSoft, borderRadius: BorderRadius.circular(12)),
                child: Center(child: PackIcon(form: '${t['form'] ?? ''}', color: kGood, size: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  const SizedBox(height: 2),
                  Text(tr(':a · zimebaki :b', {'a': t['sold_text'], 'b': t['left_text']}), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kMuted)),
                ]),
              ),
              if (t['total'] != null) Text(_m(asInt(t['total'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
            ]),
          ),
      ]),
    );
  }

  /// Hali ya hisa: how much of the shop is fine, each problem as its own
  /// tappable line (straight to that filter), and the money at risk.
  Widget _stockRow() {
    return CachedJson(
      api: _api,
      path: 'stock/insight',
      refreshTick: widget.refreshTick,
      skeleton: const Skeleton(height: 200, radius: 22),
      builder: (context, d, _) {
        final h = (d['health'] as Map?) ?? const {};
        final st = (h['states'] as Map?) ?? const {};
        final money = d['money'] as Map?;
        int n(String k) => asInt((st[k] as Map?)?['count']);
        int? v(String k) => (st[k] as Map?)?['value'] == null ? null : asInt((st[k] as Map?)?['value']);
        const order = ['ok', 'expiring', 'low', 'out', 'expired'];
        final total = math.max(1, asInt(h['products']));
        final okPct = (n('ok') * 100 / total).round();
        // Worst first; each opens the list on exactly that filter.
        const problems = [('out', 'hazipo'), ('expired', 'zimeisha'), ('low', 'chache'), ('expiring', 'muda')];
        final shown = [for (final p in problems) if (n(p.$1) > 0) p];

        Widget line(String state, String filter) {
          final look = stateLooks[state]!;
          final value = v(state);
          return Semantics(
            button: true,
            label: '${tr(look.label)} ${n(state)}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                tick();
                widget.onOpenStock(filter);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: look.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr(look.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kInk))),
                  if (value != null && value > 0) ...[
                    Text(_m(value), style: const TextStyle(fontSize: 12, color: kMuted)),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: look.soft, borderRadius: BorderRadius.circular(99)),
                    child: Text('${n(state)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: look.ink)),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: kMuted),
                ]),
              ),
            ),
          );
        }

        return InsightCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: CardTitle(tr('Hali ya hisa'))),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kPrimary),
                onPressed: () => widget.onOpenStock('zote'),
                child: Text(tr('Bidhaa zote :n', {'n': h['products'] ?? 0}), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              ShareRing(
                values: [for (final k in order) n(k)],
                colors: [for (final k in order) stateLooks[k]!.color],
                size: 96,
                stroke: 11,
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$okPct%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                  T('ziko sawa', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: T('Hakuna kilichoisha wala kinachoisha muda. Vizuri!', style: const TextStyle(fontSize: 13, color: kGood, fontWeight: FontWeight.w600)),
                      )
                    : Column(children: [for (final p in shown) line(p.$1, p.$2)]),
              ),
            ]),
            if (money != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFEEF3F1)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _money(tr('Thamani (bei ya kununua)'), asInt(money['cost']), kInk)),
                Expanded(child: _money(tr('Faida ndani yake'), asInt(money['profit']), kGood)),
                Expanded(child: _money(tr('Hatarini kwa muda'), asInt(money['at_risk']), asInt(money['at_risk']) > 0 ? kBad : kMuted)),
              ]),
            ],
          ]),
        );
      },
    );
  }

  Widget _money(String label, int v, Color c) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 2, style: const TextStyle(fontSize: 11, color: kMuted, height: 1.2)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_m(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
      );
}


/// The big Uza button (v0.46.1): green, wide, a cart, and a slow breathing
/// glow so it reads as "start here". Still when the phone asks for less motion.
class UzaButton extends StatefulWidget {
  const UzaButton({super.key, required this.label, required this.onTap, this.height = 76});

  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  State<UzaButton> createState() => _UzaButtonState();
}

class _UzaButtonState extends State<UzaButton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [Color(0xFF1F8A66), Color(0xFF0E5A44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(color: const Color(0xFF1F8A66).withValues(alpha: .22 + .18 * _c.value), blurRadius: 14 + 10 * _c.value, offset: const Offset(0, 6)),
              ],
            ),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                  Text(tr('Anza mauzo'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
