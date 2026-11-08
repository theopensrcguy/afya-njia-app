import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/brand.dart';
import '../../../core/format.dart';
import '../../../core/money.dart';
import '../../../core/i18n.dart';

/// "Wiki hii / Oktoba": one bar per day, today in mint.
///
/// It loads its own data (GET dashboard/trend), so the home screen's first
/// request stays small. Each range is fetched once and kept, so switching
/// Wiki ↔ Mwezi is instant; [refreshTick] going up (pull to refresh, coming
/// back from a sale) throws the cache away and loads again.
class TrendCard extends StatefulWidget {
  const TrendCard({super.key, required this.api, required this.hidden, required this.refreshTick});

  final ApiClient api;
  final bool hidden;
  final int refreshTick;

  @override
  State<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<TrendCard> {
  String _range = 'week';
  final Map<String, Map<String, dynamic>> _cache = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TrendCard old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) {
      _cache.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final range = _range;
    if (_cache.containsKey(range)) return;
    try {
      final data = await widget.api.get('dashboard/trend', query: {'range': range}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _cache[range] = data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _pick(String range) {
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _cache[_range];
    final from = parseDate(data?['from']);
    final title = _range == 'week' ? tr('Wiki hii') : (from != null ? monthNames[from.month - 1] : tr('Mwezi huu'));
    final total = asInt(data?['total']);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                      data == null ? ' ' : tr('Jumla :a', {'a': widget.hidden ? tr('TSh ••••••') : formatTsh(total)}),
                      style: const TextStyle(fontSize: 13, color: mutedText),
                    ),
                  ],
                ),
              ),
              _switch(),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: data != null
                ? _bars(data)
                : Center(
                    child: _error != null
                        ? TextButton(onPressed: _load, child: const T('Jaribu tena'))
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _switch() {
    Widget option(String id, String label) {
      final on = _range == id;
      return GestureDetector(
        onTap: () => _pick(id),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? brandGreen : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? Colors.white : const Color(0xFF3E5A52))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [option('week', tr('Wiki')), option('month', tr('Mwezi'))]),
    );
  }

  Widget _bars(Map<String, dynamic> data) {
    final days = ((data['days'] as List?) ?? const []).cast<Map>();
    final today = '${data['today']}';
    final maxTotal = days.fold<int>(1, (m, d) => asInt(d['total']) > m ? asInt(d['total']) : m);
    final isWeek = _range == 'week';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(child: _bar(days[i], i, isToday: '${days[i]['date']}' == today, isWeek: isWeek, maxTotal: maxTotal)),
      ],
    );
  }

  Widget _bar(Map day, int i, {required bool isToday, required bool isWeek, required int maxTotal}) {
    final value = asInt(day['total']);
    final date = parseDate(day['date']);
    // Bars keep their shape when amounts are hidden: the shape says "good or
    // slow day" without telling a customer how much the shop made.
    final height = value == 0 ? 4.0 : 4 + 68 * value / maxTotal;
    String label = '';
    if (isWeek) {
      label = weekdayShort[i];
    } else if (isToday || const [0, 7, 14, 21, 28].contains(i)) {
      label = '${date?.day ?? i + 1}';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: isWeek ? (isToday ? 14 : 10) : 5,
          height: height,
          decoration: BoxDecoration(
            color: isToday ? mintAccent : (value == 0 ? const Color(0xFFE6EEEA) : const Color(0xFFCFE2D9)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          // Month bars are ~8 px wide but "29" needs more: let the label
          // spill over its neighbours (which have no label) and stay centred.
          child: OverflowBox(
            maxWidth: 40,
            child: Text(label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                color: isToday ? brandGreen : mutedText,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              )),
          ),
        ),
      ],
    );
  }
}
