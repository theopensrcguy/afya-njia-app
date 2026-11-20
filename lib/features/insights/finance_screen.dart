import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'expenses_insight_screen.dart';
import 'forecast_screen.dart';
import 'insight_parts.dart';

/// Fedha (v0.45, canvas screen 7): the month's money in one place. Profit
/// after expenses, this month's line against last month's, the monthly goal,
/// expenses and sales by type, and the money that moved. GET insights/finance.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, required this.session});

  final Session session;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _line = UiMemory.get('fedha.line', 'mauzo');
  String _moves = 'all';
  int? _cat; // expense type in focus on the ring

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  bool get _isNow => _month.year == DateTime.now().year && _month.month == DateTime.now().month;

  void _shift(int by) {
    tick();
    setState(() => (_month = DateTime(_month.year, _month.month + by), _cat = null));
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final prevName = monthNames[(_month.month + 10) % 12];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        title: const T('Fedha', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Month switcher: last month is one tap back.
          Row(children: [
            IconButton(onPressed: () => _shift(-1), tooltip: tr('Mwezi uliopita'), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                    key: ValueKey(_key), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              ),
            ),
            IconButton(onPressed: _isNow ? null : () => _shift(1), tooltip: tr('Mwezi unaofuata'), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 6),
          CachedJson(
            api: widget.session.api,
            path: 'insights/finance',
            query: {'month': _key},
            skeleton: const Column(children: [CardSkeleton(height: 190), SizedBox(height: 14), CardSkeleton(height: 240)]),
            builder: (context, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d, prevName),
              const SizedBox(height: 14),
              _chart(d, prevName),
              if (d['target'] != null) ...[const SizedBox(height: 14), _target(d)],
              if (((d['expenses_by_type'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _expenses(d)],
              if (((d['by_category'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _categories(d)],
              if (((d['moves'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _movesCard(d)],
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _link(Icons.insights_rounded, tr('Utabiri na watu'), () => _open(ForecastScreen(session: widget.session)))),
            const SizedBox(width: 10),
            Expanded(child: _link(Icons.receipt_long_outlined, tr('Matumizi'), () => _open(ExpensesInsightScreen(session: widget.session)))),
          ]),
        ],
      ),
    );
  }

  Widget _link(IconData icon, String label, VoidCallback onTap) => InsightCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: kPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
          const Icon(Icons.chevron_right_rounded, color: kMuted, size: 20),
        ]),
      );

  // ------------------------------------------------------------ hero

  Widget _hero(Map<String, dynamic> d, String prevName) {
    final hasCosts = d['net'] != null;
    final main = hasCosts ? asInt(d['net']) : asInt(d['sales']);
    Widget part(String label, int? v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFFB7D3C9))),
            const SizedBox(height: 2),
            Text(v == null ? '—' : shortMoney(v), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          hasCosts ? tr('Faida baada ya matumizi · siku :n', {'n': d['days']}) : tr('Mauzo · siku :n', {'n': d['days']}),
          style: const TextStyle(fontSize: 13, color: Color(0xFFB7D3C9)),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(formatTsh(main),
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.5, color: main < 0 ? const Color(0xFFF9B4A6) : Colors.white)),
        ),
        const SizedBox(height: 6),
        DeltaBadge(delta: (hasCosts ? d['net_delta'] : d['sales_delta']) as num?, than: tr('kuliko :m', {'m': prevName}), onDark: true),
        const SizedBox(height: 16),
        Row(children: [
          part(tr('Mauzo'), asInt(d['sales'])),
          if (hasCosts) part(tr('Gharama ya dawa'), asInt(d['cost'])),
          if (hasCosts) part(tr('Matumizi'), asInt(d['expenses'])),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------ chart

  Widget _chart(Map<String, dynamic> d, String prevName) {
    final c = (d['chart'] as Map?) ?? const {};
    final profit = c['profit'] is List;
    final line = profit ? _line : 'mauzo';
    List<int> ints(dynamic v) => ((v as List?) ?? const []).map(asInt).toList();
    final cur = ints(line == 'faida' ? c['profit'] : c['sales']);
    final prev = ints(line == 'faida' ? c['profit_before'] : c['sales_before']);
    final color = line == 'faida' ? const Color(0xFF4D7FE0) : kPrimary;
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Mwezi huu dhidi ya uliopita')),
        if (profit) ...[
          const SizedBox(height: 12),
          SlidingSegments<String>(
            values: const ['mauzo', 'faida'],
            labels: [tr('Mauzo'), tr('Faida')],
            selected: line,
            height: 36,
            fontSize: 13,
            onChanged: (v) {
              setState(() => _line = v);
              UiMemory.set('fedha.line', v);
            },
          ),
        ],
        const SizedBox(height: 14),
        MonthLines(
          key: ValueKey('$_key$line'),
          current: cur,
          previous: prev,
          daysInMonth: asInt(d['days_in_month']),
          color: color,
          tip: cur.isEmpty ? null : '${_isNow ? tr('Leo') : tr('Mwisho')}: ${tshShort(cur.last)}',
        ),
        const SizedBox(height: 10),
        Row(children: [
          _legend(color, monthNames[_month.month - 1], solid: true),
          const SizedBox(width: 16),
          _legend(const Color(0xFF9DB0A9), prevName),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String label, {bool solid = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 3, decoration: BoxDecoration(color: solid ? c : c.withValues(alpha: .7), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
      ]);

  // ------------------------------------------------------------ target

  Widget _target(Map<String, dynamic> d) {
    final need = d['needed_per_day'];
    return InsightCard(
      child: Row(children: [
        SemiGauge(pct: d['target_pct'] as int?, color: kPrimary, track: const Color(0xFFE3EAE7), onDark: false, width: 96, caption: tr('ya lengo')),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T('Lengo la mwezi', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 4),
            Text('${tshShort(asInt(d['sales']))} / ${shortMoney(asInt(d['target']))}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            if (need != null) ...[
              const SizedBox(height: 6),
              Text(tr('Unahitaji :a kwa siku hadi mwisho wa mwezi.', {'a': formatTsh(asInt(need))}), style: const TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
            ],
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ expenses by type

  static const typeColors = [kPrimary, Color(0xFF4D7FE0), Color(0xFFE39B2E), Color(0xFF6E5A9E), Color(0xFF8A9B95), Color(0xFFD0533C)];

  Widget _expenses(Map<String, dynamic> d) {
    final rows = ((d['expenses_by_type'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = rows.fold<int>(0, (a, r) => a + asInt(r['total']));
    final focus = _cat != null && _cat! < rows.length ? _cat : null;
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Matumizi kwa aina'),
            trailing: Text(tr(':a mwezi huu', {'a': shortMoney(total)}), style: const TextStyle(fontSize: 12, color: kMuted))),
        const SizedBox(height: 14),
        Row(children: [
          ShareRing(
            values: [for (final r in rows) asInt(r['total'])],
            colors: [for (var i = 0; i < rows.length; i++) typeColors[i % typeColors.length]],
            size: 112,
            focus: focus,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(shortMoney(focus == null ? total : asInt(rows[focus]['total'])), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
              Text(focus == null ? tr('jumla') : '${total == 0 ? 0 : (asInt(rows[focus]['total']) * 100 / total).round()}%',
                  style: const TextStyle(fontSize: 11, color: kMuted)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(children: [
              for (var i = 0; i < rows.length && i < 6; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    tick();
                    setState(() => _cat = _cat == i ? null : i);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: typeColors[i % typeColors.length], shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('${rows[i]['name']}'), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: kInk, fontWeight: focus == i ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      Text(shortMoney(asInt(rows[i]['total'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------ sales by category

  Widget _categories(Map<String, dynamic> d) {
    final rows = ((d['by_category'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final max = rows.fold<int>(1, (a, r) => asInt(r['total']) > a ? asInt(r['total']) : a);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Mauzo kwa aina')),
        const SizedBox(height: 10),
        for (final r in rows.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk))),
                if (r['margin'] != null) Text(tr('faida :p%', {'p': r['margin']}), style: const TextStyle(fontSize: 12, color: kGood)),
                const SizedBox(width: 10),
                Text(shortMoney(asInt(r['total'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
              ]),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, box) => Stack(children: [
                  Container(height: 7, decoration: BoxDecoration(color: const Color(0xFFEEF3F1), borderRadius: BorderRadius.circular(99))),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: asInt(r['total']) / max),
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.curve,
                    builder: (_, v, _) => Container(
                        width: box.maxWidth * v, height: 7, decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(99))),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------ moves

  Widget _movesCard(Map<String, dynamic> d) {
    final all = ((d['moves'] as List?) ?? const []).cast<Map<String, dynamic>>();
    const kinds = [('all', 'Zote'), ('sales', 'Mauzo'), ('debt', 'Deni'), ('expense', 'Matumizi'), ('delivery', 'Mzigo')];
    final present = {for (final m in all) '${m['kind']}'};
    final list = _moves == 'all' ? all : all.where((m) => m['kind'] == _moves).toList();
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Pesa iliyoingia na kutoka')),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final k in kinds)
              if (k.$1 == 'all' || present.contains(k.$1))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChipX(label: tr(k.$2), selected: _moves == k.$1, onTap: () => setState(() => _moves = k.$1)),
                ),
          ]),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: Column(children: [
            for (final m in list)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
                child: Row(children: [
                  _moveIcon('${m['kind']}'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                      if ('${m['sub'] ?? ''}'.isNotEmpty)
                        Text(tr('${m['sub']}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
                    ]),
                  ),
                  Text(
                    '${asInt(m['amount']) >= 0 ? '+' : '−'}${formatTsh(asInt(m['amount']).abs()).replaceFirst('TSh ', '')}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: asInt(m['amount']) >= 0 ? kGood : kBad),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _moveIcon(String kind) {
    final (icon, bg, fg) = switch (kind) {
      'sales' => (Icons.point_of_sale_rounded, kGoodSoft, kGood),
      'debt' => (Icons.account_balance_wallet_outlined, const Color(0xFFEAF0FD), const Color(0xFF2F5FC4)),
      'delivery' => (Icons.local_shipping_outlined, const Color(0xFFF0ECF7), const Color(0xFF5B4790)),
      _ => (Icons.receipt_long_outlined, kBadSoft, kBad),
    };
    return Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 19, color: fg));
  }
}
