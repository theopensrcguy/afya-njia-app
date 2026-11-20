import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'insight_parts.dart';

/// Utabiri na watu (v0.45, canvas screen 9): where the month lands at this
/// pace, what it takes to reach the goal, who sold, what sells and what
/// sleeps on the shelf. GET insights/forecast.
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key, required this.session});

  final Session session;

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  String? _who; // seller tapped
  String _list = 'top';

  static const _people = [kPrimary, Color(0xFF4D7FE0), Color(0xFFE39B2E), Color(0xFF6E5A9E), Color(0xFF8A9B95)];

  @override
  Widget build(BuildContext context) {
    final month = monthNames[DateTime.now().month - 1];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, surfaceTintColor: Colors.transparent, title: const T('Utabiri na watu', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          CachedJson(
            api: widget.session.api,
            path: 'insights/forecast',
            skeleton: const Column(children: [CardSkeleton(height: 260), SizedBox(height: 14), CardSkeleton(height: 120)]),
            builder: (context, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered([
              _hero(d, month),
              const SizedBox(height: 12),
              _activity(d),
              if (((d['sellers'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _sellers(d)],
              const SizedBox(height: 14),
              _lists(d),
            ])),
          ),
        ],
      ),
    );
  }

  Widget _hero(Map<String, dynamic> d, String month) {
    final target = d['target'] == null ? null : asInt(d['target']);
    final forecast = asInt(d['forecast']);
    final short = asInt(d['short_by']);
    final advice = target == null
        ? tr('Weka lengo la mauzo kwa siku ili uone kama mwezi utafika.')
        : short > 0
            ? tr('Kwa mwendo huu utakosa lengo kwa :a. Ongeza mauzo ya :b kwa siku.', {'a': formatTsh(short), 'b': formatTsh(asInt(d['extra_per_day']))})
            : tr('Kwa mwendo huu utavuka lengo kwa :a. Endelea hivyo.', {'a': formatTsh(forecast - target)});
    Widget meter(String label, int pct, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted))),
              Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (pct / 100).clamp(0, 1).toDouble()),
                duration: Motion.of(context, Motion.slow),
                curve: Motion.curve,
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 7, color: c, backgroundColor: const Color(0xFFEEF3F1)),
              ),
            ),
          ]),
        );
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Utabiri wa mauzo ya :m', {'m': month}), style: const TextStyle(fontSize: 13, color: kMuted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUp(value: forecast, format: formatTsh, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.5, color: kInk)),
        ),
        Text(tr(':a mpaka leo (siku :n kati ya :m)', {'a': tshShort(asInt(d['sales'])), 'n': d['days_gone'], 'm': d['days_in_month']}),
            style: const TextStyle(fontSize: 13, color: kMuted)),
        const SizedBox(height: 14),
        Row(children: [
          meter(tr('Muda umepita'), asInt(d['time_pct']), const Color(0xFF8A9B95)),
          if (d['target_pct'] != null) ...[
            const SizedBox(width: 14),
            meter(tr('Lengo limefikiwa'), asInt(d['target_pct']), kPrimary),
          ],
        ]),
        const SizedBox(height: 16),
        MonthLines(
          current: ((d['chart'] as List?) ?? const []).map(asInt).toList(),
          daysInMonth: asInt(d['days_in_month']),
          forecastTo: forecast,
          target: target,
          tip: tr('Utabiri :a', {'a': shortMoney(forecast)}),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: short > 0 ? kBadSoft : kGoodSoft, borderRadius: BorderRadius.circular(14)),
          child: Text(advice, style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: short > 0 ? kBad : kGood)),
        ),
      ]),
    );
  }

  Widget _activity(Map<String, dynamic> d) {
    final a = (d['activity'] as Map?) ?? const {};
    final best = a['best_day'];
    Widget tile(String value, String label) => Expanded(
          child: InsightCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk))),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, color: kMuted)),
            ]),
          ),
        );
    return Row(children: [
      tile('${a['sales_per_day'] ?? 0}', tr('Mauzo kwa siku')),
      const SizedBox(width: 10),
      tile(a['items_per_sale'] == null ? '—' : '${a['items_per_sale']}', tr('Bidhaa kwa mauzo')),
      const SizedBox(width: 10),
      tile(best == null ? '—' : weekdayShort[asInt(best).clamp(0, 6)], tr('Siku bora')),
    ]);
  }

  Widget _sellers(Map<String, dynamic> d) {
    final rows = ((d['sellers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = rows.fold<int>(0, (a, r) => a + asInt(r['total']));
    final focus = rows.indexWhere((r) => r['name'] == _who);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Wauzaji mwezi huu')),
        const SizedBox(height: 4),
        T('Gusa jina kuona wastani wake na mauzo aliyofuta.', style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 14),
        Row(children: [
          ShareRing(
            values: [for (final r in rows) asInt(r['total'])],
            colors: [for (var i = 0; i < rows.length; i++) _people[i % _people.length]],
            size: 104,
            focus: focus < 0 ? null : focus,
            center: Text(shortMoney(focus < 0 ? total : asInt(rows[focus]['total'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) _seller(i, rows[i]),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _seller(int i, Map<String, dynamic> r) {
    final on = _who == r['name'];
    final role = r['role'] == 'owner' ? tr('Mmiliki') : tr('Msaidizi');
    final sub = on
        ? tr('wastani :a · amefuta :n', {'a': formatTsh(asInt(r['average'])).replaceFirst('TSh ', ''), 'n': r['voids'] ?? 0})
        : '$role · ${tr('mauzo :n', {'n': r['count']})}';
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          tick();
          setState(() => _who = on ? null : '${r['name']}');
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(color: on ? kBg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: _people[i % _people.length], shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
              ]),
            ),
            Text(shortMoney(asInt(r['total'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          ]),
        ),
      ),
    );
  }

  Widget _lists(Map<String, dynamic> d) {
    final top = ((d['top'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final slow = d['slow'] as Map?;
    final hasSlow = slow != null && ((slow['rows'] as List?) ?? const []).isNotEmpty;
    final list = hasSlow ? _list : 'top';
    final rows = list == 'top' ? top : ((slow!['rows'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final note = list == 'top'
        ? tr('Zinazoleta pesa zaidi mwezi huu.')
        : tr('Pesa iliyolala rafuni: :a kwa bei ya kununua. Fikiria punguzo au usiagize tena.', {'a': formatTsh(asInt(slow!['value']))});
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasSlow)
          SlidingSegments<String>(
            values: const ['top', 'slow'],
            labels: [tr('Zinazouzwa zaidi'), tr('Zimelala')],
            selected: list,
            height: 36,
            fontSize: 13,
            onChanged: (v) => setState(() => _list = v),
          )
        else
          CardTitle(tr('Zinazouzwa zaidi')),
        const SizedBox(height: 10),
        Text(note, style: const TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: T('Bado hakuna mauzo mwezi huu.', style: TextStyle(color: kMuted))),
        for (var i = 0; i < rows.length; i++) _row(i, rows[i], list == 'top'),
      ]),
    );
  }

  Widget _row(int i, Map<String, dynamic> r, bool top) {
    final String sub;
    final int amount;
    if (top) {
      sub = [
        '${r['unit'] ?? ''} ${r['qty'] ?? ''}'.trim(),
        if (r['margin'] != null) tr('faida :p%', {'p': r['margin']}),
      ].where((s) => s.isNotEmpty).join(' · ');
      amount = asInt(r['total']);
    } else {
      final idle = r['idle_days'];
      sub = idle == null ? tr('haijawahi kuuzwa') : tr('hakuna mauzo siku :n', {'n': idle});
      amount = asInt(r['value_at_cost']);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: top ? kGoodSoft : kBadSoft, shape: BoxShape.circle),
          child: Center(child: Text(top ? '${i + 1}' : '!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: top ? kGood : kBad))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
        Text(formatTsh(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: top ? kInk : kBad)),
      ]),
    );
  }
}
