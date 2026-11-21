import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/range_picker.dart';
import '../../core/share_export.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/units.dart';
import '../insights/insight_parts.dart';

/// Mauzo (v0.45.2): any day's sales, not only today's. The owner sees
/// everyone's; a helper only his own (the server decides).
///
/// A day strip (Leo, Jana, the week) plus a calendar for older days; a dark
/// summary (total, count, average, how it was paid); the day's hours as bars;
/// search and payment chips; the sales grouped by hour. Tapping a sale shows
/// it as a receipt, with "Futa" (a reason is required). Cancelled sales stay,
/// crossed out: nothing is deleted.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  late DateTime _day = _today;
  DateTime? _to; // set: a range from _day to _to (both included)
  final _q = TextEditingController();
  String _pay = 'all';
  int _tick = 0;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  ApiClient get _api => widget.session.api;
  bool get _allSales => widget.session.user!.can(Perm.viewShopSales);
  String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String get _key => _to == null ? _iso(_day) : '${_iso(_day)}_${_iso(_to!)}';
  bool get _range => _to != null;
  Map<String, String> get _query => _to == null ? {'date': _iso(_day)} : {'from': _iso(_day), 'to': _iso(_to!)};

  /// "10 Okt – 2 Nov" (the year only when it isn't this year).
  String get _periodText {
    if (_to == null) return swahiliDate(_day);
    String short(DateTime d) {
      final m = monthNames[d.month - 1];
      return '${d.day} ${m.length > 3 ? m.substring(0, 3) : m}${d.year == _today.year ? '' : ' ${d.year}'}';
    }

    return '${short(_day)} – ${short(_to!)}';
  }
  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _setDay(DateTime d) {
    if (d == _day && _to == null) return;
    tick();
    setState(() => (_day = d, _to = null, _pay = 'all'));
  }

  /// One day or a period: the calendar lets you tap one day, or a first and
  /// a last day (e.g. 10 Oct – 2 Nov). At most 93 days at a time.
  Future<void> _pickDay() async {
    // Tap the days on a calendar (or a quick choice); no typing (v0.46.1).
    final r = await pickDayOrRange(
      context,
      first: DateTime(2024),
      last: _today,
      initial: DateTimeRange(start: _day, end: _to ?? _day),
    );
    if (r == null || !mounted) return;
    var start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day);
    if (end.difference(start).inDays > 92) {
      start = end.subtract(const Duration(days: 92));
      _toast(tr('Kipindi kirefu zaidi ni siku 93: kimeanzia :d.', {'d': swahiliDate(start)}));
    }
    tick();
    setState(() => (_day = start, _to = end == start ? null : end, _pay = 'all'));
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _dayName(DateTime d) {
    final diff = _today.difference(d).inDays;
    if (diff == 0) return tr('Leo');
    if (diff == 1) return tr('Jana');
    return '${weekdayShort[d.weekday - 1]} ${d.day}';
  }

  bool _voided(Map<String, dynamic> s) => s['status'] == 'voided';

  /// Each sale as its payment parts: {method: amount}.
  Map<String, int> _parts(Map<String, dynamic> s) {
    final parts = (s['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (parts.isNotEmpty) return {for (final p in parts) '${p['method']}': asInt(p['amount'])};
    return {'${s['payment_method']}': asInt(s['total'])};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _topBar(),
          _dayStrip(),
          Expanded(
            child: CachedJson(
              api: _api,
              path: 'sales',
              query: _query,
              refreshTick: _tick,
              skeleton: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [CardSkeleton(height: 170), SizedBox(height: 14), CardSkeleton(height: 120)]),
              ),
              builder: (context, data, reload) {
                final sales = ((data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _tick++),
                  child: _body(sales),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Row(children: [
          Semantics(
            button: true,
            label: tr('Rudi'),
            excludeSemantics: true,
            child: Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.chevron_left_rounded, color: kInk),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_allSales ? tr('Mauzo') : tr('Mauzo yangu'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -.4)),
          ),
          Semantics(
            button: true,
            label: tr('Chagua siku'),
            excludeSemantics: true,
            child: Pressable(
              onTap: _pickDay,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_month_outlined, size: 18, color: kPrimary),
                  const SizedBox(width: 6),
                  Text(_periodText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Share these sales (PDF / Excel) with someone outside the app (v0.47).
          Semantics(
            button: true,
            label: tr('Shiriki mauzo'),
            excludeSemantics: true,
            child: Pressable(
              onTap: () => shareSales(context, api: _api, from: _day, to: _to ?? _day,
                  method: const ['cash', 'mobile', 'insurance', 'credit'].contains(_pay) ? _pay : null),
              child: Container(
                width: 44,
                height: 44,
                // Quiet, like Hisa's top-bar squares (v0.47.2: the dark one shouted).
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.ios_share_rounded, color: kPrimary, size: 20),
              ),
            ),
          ),
        ]),
      );

  /// The last 7 days, today last on the right, as they'd be said.
  Widget _dayStrip() {
    final days = [for (var i = 6; i >= 0; i--) _today.subtract(Duration(days: i))];
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        children: [
          for (final d in days.reversed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChipX(label: _dayName(d), selected: !_range && d == _day, onTap: () => _setDay(d)),
            ),
        ],
      ),
    );
  }

  Widget _body(List<Map<String, dynamic>> sales) {
    final done = sales.where((s) => !_voided(s)).toList();
    final voided = sales.length - done.length;
    // Filters: payment kind (a split sale counts under each of its parts),
    // cancelled, and the search on product names or the receipt number.
    final q = _q.text.trim().toLowerCase();
    bool match(Map<String, dynamic> s) {
      if (_pay == 'voided') {
        if (!_voided(s)) return false;
      } else if (_pay != 'all' && (_voided(s) || !_parts(s).containsKey(_pay))) {
        return false;
      }
      if (q.isEmpty) return true;
      final names = ((s['items'] as List?) ?? const []).map((i) => '${((i as Map)['product'] as Map?)?['name'] ?? ''}'.toLowerCase());
      return '${s['receipt_number']}'.toLowerCase().contains(q) || names.any((n) => n.contains(q)) || '${(s['user'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q);
    }

    final shown = sales.where(match).toList()..sort((a, b) => '${b['sold_at']}'.compareTo('${a['sold_at']}'));
    // One day: by hour. A period: by day.
    final byHour = <int, List<Map<String, dynamic>>>{};
    for (final s in shown) {
      final at = parseDate(s['sold_at'])?.toLocal();
      final k = at == null ? 0 : (_range ? at.year * 10000 + at.month * 100 + at.day : at.hour);
      byHour.putIfAbsent(k, () => []).add(s);
    }
    final counts = <String, int>{};
    for (final s in done) {
      for (final k in _parts(s).keys) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }

    var n = 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
      children: [
        Appear(index: n++, child: _summary(done, voided)),
        if (done.isNotEmpty) ...[const SizedBox(height: 12), Appear(index: n++, child: _range ? _days(done) : _hours(done))],
        const SizedBox(height: 14),
        if (sales.isNotEmpty) ...[
          TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Tafuta dawa, risiti au muuzaji'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_q.clear),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChipX(label: tr('Zote'), selected: _pay == 'all', count: done.length, onTap: () => setState(() => _pay = 'all')),
            for (final k in const ['cash', 'mobile', 'insurance', 'credit'])
              if ((counts[k] ?? 0) > 0)
                ChoiceChipX(label: paymentLabels[k] ?? k, selected: _pay == k, count: counts[k], onTap: () => setState(() => _pay = k)),
            if (voided > 0)
              ChoiceChipX(label: tr('Yaliyofutwa'), selected: _pay == 'voided', count: voided, dot: kBad, onTap: () => setState(() => _pay = 'voided')),
          ]),
        ],
        if (sales.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(children: [
              const Icon(Icons.receipt_long_outlined, size: 44, color: Color(0xFFB8C4C0)),
              const SizedBox(height: 10),
              Text(_range ? tr('Hakuna mauzo kipindi hiki.') : (_day == _today ? tr('Hakuna mauzo leo bado.') : tr('Hakuna mauzo siku hii.')), style: const TextStyle(color: kMuted)),
            ]),
          )
        else if (shown.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 28), child: Center(child: T('Hakuna kinacholingana.', style: const TextStyle(color: kMuted)))),
        for (final h in byHour.keys)
          Appear(index: n++, child: _hourGroup(h, byHour[h]!)),
      ],
    );
  }

  // ------------------------------------------------------------ summary

  Widget _summary(List<Map<String, dynamic>> done, int voided) {
    final total = done.fold<int>(0, (a, s) => a + asInt(s['total']));
    final pay = <String, int>{};
    for (final s in done) {
      _parts(s).forEach((k, v) => pay[k] = (pay[k] ?? 0) + v);
    }
    const looks = [('cash', kMint), ('mobile', Color(0xFF8FB2FF)), ('insurance', Color(0xFFF2C46B)), ('credit', Color(0xFFF9B4A6))];
    final parts = [for (final l in looks) if ((pay[l.$1] ?? 0) > 0) l];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              !_range && _day == _today ? (_allSales ? tr('Mauzo ya leo') : tr('Mauzo yangu ya leo')) : tr('Mauzo ya :d', {'d': _periodText}),
              style: const TextStyle(fontSize: 13, color: Color(0xFFB7D3C9)),
            ),
          ),
          if (voided > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: const Color(0x33F9B4A6), borderRadius: BorderRadius.circular(99)),
              child: Text(tr('yaliyofutwa :n', {'n': voided}), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFF9B4A6))),
            ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUp(
            key: ValueKey(_key),
            value: total,
            format: formatTsh,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -.5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          done.isEmpty ? '—' : tr('mauzo :n · wastani :a', {'n': done.length, 'a': formatTsh(total ~/ done.length)}),
          style: const TextStyle(fontSize: 13, color: Color(0xFFB7D3C9)),
        ),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                for (final p in parts)
                  Expanded(flex: math.max(1, (pay[p.$1]! * 1000 ~/ math.max(1, total))), child: Container(margin: const EdgeInsets.only(right: 2), color: p.$2)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            for (final p in parts)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: p.$2, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${paymentLabels[p.$1]} ', style: const TextStyle(fontSize: 12, color: Color(0xFFB7D3C9))),
                Text(shortMoney(pay[p.$1]!), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
          ]),
        ],
      ]),
    );
  }

  /// Sales by hour of the day, so the busy hours show at a glance.
  Widget _hours(List<Map<String, dynamic>> done) {
    final per = <int, int>{};
    for (final s in done) {
      final h = parseDate(s['sold_at'])?.toLocal().hour;
      if (h != null) per[h] = (per[h] ?? 0) + asInt(s['total']);
    }
    final first = math.min(8, per.keys.fold<int>(24, math.min));
    final last = math.max(20, per.keys.fold<int>(0, math.max));
    final max = math.max(1, per.values.fold<int>(0, math.max));
    final peak = per.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Kwa saa'))),
          Text(tr('kilele saa :h', {'h': '${_two(peak)}:00'}), style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 74,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var h = first; h <= last; h++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (per[h] ?? 0) / max),
                    duration: Motion.of(context, Duration(milliseconds: 380 + (h - first) * 25)),
                    curve: Motion.curve,
                    builder: (_, v, _) => Container(
                      height: math.max(3, v * 54),
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: per[h] == null ? const Color(0xFFEEF3F1) : (h == peak ? kPrimary : const Color(0xFFCDEFE0)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 12,
                    child: (h - first) % 3 == 0 ? Text('$h', style: const TextStyle(fontSize: 9.5, color: kMuted)) : null,
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  /// A period: one bar per day, the best day marked.
  Widget _days(List<Map<String, dynamic>> done) {
    final per = <int, int>{};
    for (final s in done) {
      final at = parseDate(s['sold_at'])?.toLocal();
      if (at == null) continue;
      final k = DateTime(at.year, at.month, at.day).difference(_day).inDays;
      per[k] = (per[k] ?? 0) + asInt(s['total']);
    }
    final days = _to!.difference(_day).inDays + 1;
    final max = math.max(1, per.values.fold<int>(0, math.max));
    final best = per.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final bestDay = _day.add(Duration(days: best));
    final avg = per.values.fold<int>(0, (a, v) => a + v) ~/ days;
    final step = days <= 14 ? 2 : (days <= 31 ? 5 : 10);
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Kwa siku'))),
          Text(tr('wastani :a kwa siku', {'a': shortMoney(avg)}), style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 74,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < days; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (per[i] ?? 0) / max),
                    duration: Motion.of(context, Duration(milliseconds: 380 + math.min(i, 30) * 12)),
                    curve: Motion.curve,
                    builder: (_, v, _) => Container(
                      height: math.max(3, v * 54),
                      margin: EdgeInsets.symmetric(horizontal: days > 40 ? .5 : 1.5),
                      decoration: BoxDecoration(
                        color: per[i] == null ? const Color(0xFFEEF3F1) : (i == best ? kPrimary : const Color(0xFFCDEFE0)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 12,
                    child: i % step == 0
                        ? OverflowBox(maxWidth: 40, child: Text('${_day.add(Duration(days: i)).day}', style: const TextStyle(fontSize: 9.5, color: kMuted)))
                        : null,
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(tr('Siku bora: :d (:a)', {'d': swahiliDate(bestDay), 'a': formatTsh(per[best]!)}), style: const TextStyle(fontSize: 12, color: kMuted)),
      ]),
    );
  }

  // ------------------------------------------------------------ list

  Widget _hourGroup(int h, List<Map<String, dynamic>> list) {
    final sum = list.where((s) => !_voided(s)).fold<int>(0, (a, s) => a + asInt(s['total']));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Text(_range ? swahiliDate(DateTime(h ~/ 10000, h ~/ 100 % 100, h % 100)) : tr('Saa :h', {'h': '${_two(h)}:00'}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(width: 8),
            Text(tr('mauzo :n', {'n': list.length}), style: const TextStyle(fontSize: 12, color: kMuted)),
            const Spacer(),
            Text(formatTsh(sum), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMuted)),
          ]),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 70, color: Color(0xFFEEF3F1)),
              _row(list[i]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final voided = _voided(s);
    final at = parseDate(s['sold_at']);
    final items = mergeSaleItems((s['items'] as List?) ?? const []);
    final first = items.isEmpty ? '${s['receipt_number']}' : '${items.first['name']}';
    final more = items.length - 1;
    final seller = '${(s['user'] as Map?)?['name'] ?? ''}';
    final sub = [if (_allSales && seller.isNotEmpty) seller, paymentText(s)].join(' · ');
    return InkWell(
      onTap: () => _detail(s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(children: [
          Container(
            width: 46,
            height: 40,
            decoration: BoxDecoration(color: voided ? kBadSoft : kGoodSoft, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(at == null ? '—' : formatTime(at),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: voided ? kBad : const Color(0xFF0E5A44))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: first),
                  if (more > 0) TextSpan(text: '  +$more', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: voided ? kMuted : kInk, decoration: voided ? TextDecoration.lineThrough : null),
              ),
              const SizedBox(height: 2),
              Text(voided ? tr('Imefutwa: :a', {'a': s['void_reason'] ?? ''}) : sub,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: voided ? kBad : kMuted)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatTsh(asInt(s['total'])).replaceFirst('TSh ', ''),
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w700, color: voided ? kMuted : kInk, decoration: voided ? TextDecoration.lineThrough : null)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ one sale

  void _detail(Map<String, dynamic> s) {
    tick();
    final voided = _voided(s);
    final items = mergeSaleItems((s['items'] as List?) ?? const []);
    final discount = asInt(s['discount']);
    final at = parseDate(s['sold_at']);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['receipt_number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 2),
                  Text(
                    [if (at != null) '${swahiliDate(at.toLocal())} · ${formatTime(at)}', '${(s['user'] as Map?)?['name'] ?? ''}'].join(' · '),
                    style: const TextStyle(fontSize: 13, color: kMuted),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: voided ? kBadSoft : kGoodSoft, borderRadius: BorderRadius.circular(99)),
                child: Text(voided ? tr('Imefutwa') : tr('Imekamilika'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: voided ? kBad : const Color(0xFF0E5A44))),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${i['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                          Text('× ${i['quantity']} ${unitLabel(i['unit'] as String?, i['quantity'] as int)}', style: const TextStyle(fontSize: 12, color: kMuted)),
                        ]),
                      ),
                      Text(formatTsh(asInt(i['line_total'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                    ]),
                  ),
                const Divider(height: 18, color: Color(0xFFDCE5E1)),
                if (discount > 0) _line(tr('Punguzo'), '− ${formatTsh(discount)}'),
                _line(tr('Jumla'), formatTsh(asInt(s['total'])), bold: true),
                const SizedBox(height: 4),
                _line(tr('Malipo'), paymentText(s)),
              ]),
            ),
            // The receipt again, any day after (v0.47): print, PDF, WhatsApp.
            const SizedBox(height: 12),
            Row(children: [
              for (final (how, icon, label) in [
                ('open', Icons.print_rounded, tr('Chapisha / PDF')),
                ('wa', Icons.chat_rounded, tr('WhatsApp')),
                ('copy', Icons.link_rounded, tr('Kiungo')),
              ]) ...[
                if (how != 'open') const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => shareReceipt(sheet, api: _api, saleId: asInt(s['id']), how: how),
                    icon: Icon(icon, size: 18),
                    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ]),
            if (voided) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kBadSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  tr('Imefutwa:a.', {'a': parseDate(s['voided_at']) != null ? tr(' saa :a', {'a': formatTime(parseDate(s['voided_at'])!)}) : ''}) +
                      tr(' Sababu: :a', {'a': s['void_reason'] ?? '-'}),
                  style: const TextStyle(color: kBad),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: dangerRed,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.cancel_outlined),
                label: const T('Futa mauzo haya'),
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _void(s);
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    final style = TextStyle(fontSize: bold ? 17 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: kInk);
    return Row(children: [Expanded(child: Text(label, style: style.copyWith(color: bold ? kInk : kMuted))), Text(value, style: style)]);
  }

  /// Cancel a sale. A reason is required. The server checks the rules:
  /// a helper may only cancel his own sale within a few minutes.
  Future<void> _void(Map<String, dynamic> s) async {
    final reason = await askText(
      context,
      title: tr('Futa :a?', {'a': s['receipt_number']}),
      message: tr('Jumla :a. Dawa zitarudishwa kwenye hisa.', {'a': formatTsh(asInt(s['total']))}),
      label: tr('Sababu (lazima)'),
      hint: tr('Mf. dawa isiyo sahihi'),
      confirm: tr('Futa'),
      danger: true,
      required: true,
    );
    if (reason == null || !mounted) return;
    try {
      await _api.post('sales/${s['id']}/void', {'reason': reason});
      _message(tr('Mauzo yamefutwa. Dawa zimerudi kwenye hisa.'));
      setState(() => _tick++);
    } on ApiException catch (e) {
      _message(e.message, isError: true);
    }
  }

  void _message(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }
}
