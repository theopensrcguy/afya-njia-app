import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../expenses/matumizi_screen.dart';
import 'insight_parts.dart';

/// Matumizi at a glance (v0.45, canvas screen 8): how much went out, by type
/// and against sales, six months of money in and out, and the regular costs
/// coming up. GET insights/expenses?period=wiki|mwezi|miezi6. Recording a new
/// expense is the existing Matumizi screen.
class ExpensesInsightScreen extends StatefulWidget {
  const ExpensesInsightScreen({super.key, required this.session});

  final Session session;

  @override
  State<ExpensesInsightScreen> createState() => _ExpensesInsightScreenState();
}

class _ExpensesInsightScreenState extends State<ExpensesInsightScreen> {
  String _period = UiMemory.get('matumizi.period', 'mwezi');
  int? _open; // the type expanded
  int _tick = 0;

  static const _colors = [
    (kPrimary, kGoodSoft),
    (Color(0xFF4D7FE0), Color(0xFFEAF0FD)),
    (Color(0xFFE39B2E), Color(0xFFFDF1E3)),
    (Color(0xFF6E5A9E), Color(0xFFF0ECF7)),
    (Color(0xFF8A9B95), Color(0xFFEEF3F1)),
    (Color(0xFFD0533C), kBadSoft),
  ];

  Future<void> _add() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatumiziScreen(session: widget.session)));
    if (mounted) setState(() => _tick++);
  }

  String get _periodText => switch (_period) { 'wiki' => tr('wiki hii'), 'miezi6' => tr('miezi 6'), _ => tr('mwezi huu') };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, surfaceTintColor: Colors.transparent, title: const T('Matumizi', style: TextStyle(fontWeight: FontWeight.w700))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const T('Ongeza matumizi', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SlidingSegments<String>(
            values: const ['wiki', 'mwezi', 'miezi6'],
            labels: [tr('Wiki'), tr('Mwezi'), tr('Miezi 6')],
            selected: _period,
            height: 40,
            fontSize: 13,
            onChanged: (v) {
              setState(() => (_period = v, _open = null));
              UiMemory.set('matumizi.period', v);
            },
          ),
          const SizedBox(height: 14),
          CachedJson(
            api: widget.session.api,
            path: 'insights/expenses',
            query: {'period': _period},
            refreshTick: _tick,
            skeleton: const Column(children: [CardSkeleton(height: 220), SizedBox(height: 14), CardSkeleton(height: 120)]),
            builder: (context, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered([
              _hero(d),
              const SizedBox(height: 12),
              _twoTiles(d),
              for (final due in ((d['due'] as List?) ?? const []).cast<Map<String, dynamic>>()) ...[const SizedBox(height: 12), _due(due)],
              const SizedBox(height: 14),
              _flow(d),
              if (((d['types'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _types(d)],
            ])),
          ),
        ],
      ),
    );
  }

  Widget _hero(Map<String, dynamic> d) {
    final types = ((d['types'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return InsightCard(
      child: Column(children: [
        ShareRing(
          values: [for (final t in types) asInt(t['total'])],
          colors: [for (var i = 0; i < types.length; i++) _colors[i % _colors.length].$1],
          size: 200,
          stroke: 18,
          half: true,
          focus: _open,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatTsh(asInt(d['total'])), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
            Text(_periodText, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
        const SizedBox(height: 8),
        DeltaBadge(delta: d['delta'] as num?, upIsGood: false, than: tr('kuliko kipindi kilichopita')),
      ]),
    );
  }

  Widget _twoTiles(Map<String, dynamic> d) {
    final share = d['share_of_sales'] as num?;
    final (note, color) = share == null
        ? ('—', kMuted)
        : share < 5
            ? (tr('chini ya 5%: vizuri'), kGood)
            : share < 10
                ? (tr('5–10%: angalia'), const Color(0xFF7A4A12))
                : (tr('zaidi ya 10%: juu'), kBad);
    Widget tile(String label, String value, String sub, Color subColor) => Expanded(
          child: InsightCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk))),
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: subColor)),
            ]),
          ),
        );
    return Row(children: [
      tile(tr('Matumizi / mauzo'), share == null ? '—' : '$share%', note, color),
      const SizedBox(width: 10),
      tile(tr('Wastani kwa siku'), formatTsh(asInt(d['per_day'])), _periodText, kMuted),
    ]);
  }

  Widget _due(Map<String, dynamic> due) {
    final days = asInt(due['days']);
    final date = DateTime.tryParse('${due['date']}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFDF1E3), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.event_repeat_rounded, color: Color(0xFF7A4A12)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${due['name']}: ${formatTsh(asInt(due['amount']))}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF7A4A12))),
            Text(
              days == 0
                  ? tr('Inatarajiwa leo')
                  : tr('Hulipwa tarehe :d · siku :n zimebaki', {'d': date?.day ?? '', 'n': days}),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A4A12)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _flow(Map<String, dynamic> d) {
    final flow = ((d['flow'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final max = math.max(1, flow.fold<int>(0, (a, f) => math.max(a, math.max(asInt(f['in']), asInt(f['out'])))));
    const out = Color(0xFFE39B2E);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Pesa iliyoingia na kutoka'), trailing: T('miezi 6', style: const TextStyle(fontSize: 12, color: kMuted))),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final f in flow)
              Expanded(
                child: Semantics(
                  label: '${f['month']}: ${tr('Mauzo')} ${formatTsh(asInt(f['in']))}, ${tr('Matumizi + mizigo')} ${formatTsh(asInt(f['out']))}',
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _bar(asInt(f['in']) / max, kPrimary),
                      const SizedBox(width: 3),
                      _bar(asInt(f['out']) / max, out),
                    ]),
                    const SizedBox(height: 6),
                    Text(_monthShort('${f['month']}'), style: const TextStyle(fontSize: 11, color: kMuted)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _key(kPrimary, tr('Mauzo')),
          const SizedBox(width: 16),
          _key(out, tr('Matumizi + mizigo')),
        ]),
      ]),
    );
  }

  String _monthShort(String ym) {
    final m = int.tryParse(ym.split('-').last) ?? 1;
    final name = monthNames[(m - 1).clamp(0, 11)];
    return name.length > 3 ? name.substring(0, 3) : name;
  }

  Widget _bar(double v, Color c) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: Motion.of(context, Motion.slow),
        curve: Motion.curve,
        builder: (_, x, _) => Container(width: 11, height: math.max(3, x * 105), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5))),
      );

  Widget _key(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
      ]);

  Widget _types(Map<String, dynamic> d) {
    final types = ((d['types'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = math.max(1, asInt(d['total']));
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Kwa aina')),
        const SizedBox(height: 6),
        for (var i = 0; i < types.length; i++) _type(i, types[i], total),
      ]),
    );
  }

  Widget _type(int i, Map<String, dynamic> t, int total) {
    final (color, soft) = _colors[i % _colors.length];
    final open = _open == i;
    final items = ((t['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final delta = t['delta'] as num?;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
      child: Column(children: [
        InkWell(
          onTap: () {
            tick();
            setState(() => _open = open ? null : i);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('${(asInt(t['total']) * 100 / total).round()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('${t['name']}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  Text(tr('malipo :n', {'n': t['count']}), style: const TextStyle(fontSize: 12, color: kMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatTsh(asInt(t['total'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                if (delta != null) DeltaBadge(delta: delta, upIsGood: false),
              ]),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: Motion.of(context, Motion.fast),
                child: const Icon(Icons.expand_more_rounded, color: kMuted),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 8, 10),
                  child: Column(children: [
                    for (final e in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              [if ('${e['note'] ?? ''}'.isNotEmpty) '${e['note']}', _dayText('${e['date']}')].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: kMuted),
                            ),
                          ),
                          Text(formatTsh(asInt(e['amount'])).replaceFirst('TSh ', ''), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
                        ]),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }

  String _dayText(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : swahiliDate(d);
  }
}
