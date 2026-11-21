import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/smooth.dart';

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _muted = Color(0xFF5B6F69);

/// Which stock-take to start (v0.46.1). How pharmacies really do it:
///  * Hesabu kamili: everything, once or twice a year (year end, a new manager).
///  * Kwa rafu: cycle counting, one or two aisles a week, so every shelf is
///    counted every month or two without closing the shop. The aisle counted
///    longest ago is first.
///  * Zinazoleta pesa (A): the few products that make 80% of sales, every
///    month: a gap there costs the most.
///  * Zinazoisha muda: what expires within 90 days, to find it and sell it first.
///  * Ukaguzi wa ghafla: 10 products at random, any day, to keep counts honest.
/// Returns {scope, ids, note}, or null.
Future<Map<String, dynamic>?> pickCountPlan(BuildContext context, ApiClient api) async {
  Map<String, dynamic>? plan;
  try {
    plan = await api.get('stock-counts/plan') as Map<String, dynamic>;
  } on ApiException {
    // Without the plan the choices still work; the numbers just don't show.
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _PlanSheet(plan: plan ?? const {}),
  );
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.plan});

  final Map<String, dynamic> plan;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  String _scope = 'category';
  final _aisles = <int>{};

  @override
  void initState() {
    super.initState();
    final aisles = ((widget.plan['aisles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    // The aisle counted longest ago is ticked already: that's the one due.
    if (aisles.isNotEmpty) {
      _aisles.add(asInt(aisles.first['id']));
    } else {
      _scope = 'full';
    }
  }

  String _ago(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return tr('haijawahi kuhesabiwa');
    final days = DateTime.now().difference(d.toLocal()).inDays;
    return days == 0 ? tr('imehesabiwa leo') : tr('siku :n zilizopita', {'n': days});
  }

  @override
  Widget build(BuildContext context) {
    final counts = ((widget.plan['counts'] as Map?) ?? const {}).cast<String, dynamic>();
    final aisles = ((widget.plan['aisles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final lastFull = widget.plan['last_full_at'] as String?;
    final options = <(String, IconData, String, String, String?)>[
      if (aisles.isNotEmpty) ('category', Icons.shelves, tr('Kwa rafu'), tr('Rafu moja au mbili kwa wiki; kila rafu inapitiwa kila mwezi.'), null),
      ('priority', Icons.star_rounded, tr('Zinazoleta pesa (A)'), tr('Bidhaa chache zinazoleta 80% ya mauzo. Kila mwezi.'), counts['priority'] == null ? null : tr('bidhaa :n', {'n': counts['priority']})),
      ('expiring', Icons.hourglass_bottom_rounded, tr('Zinazoisha muda'), tr('Zinazoisha ndani ya siku 90: zipate, ziuze kwanza.'), counts['expiring'] == null ? null : tr('bidhaa :n', {'n': counts['expiring']})),
      ('spot', Icons.shuffle_rounded, tr('Ukaguzi wa ghafla'), tr('Bidhaa 10 za kubahatisha, siku yoyote. Huweka hesabu za kweli.'), null),
      ('full', Icons.inventory_rounded, tr('Hesabu kamili'), lastFull == null ? tr('Kila kitu dukani. Mara 1–2 kwa mwaka.') : tr('Kila kitu. Ya mwisho: :a.', {'a': _ago(lastFull)}),
          counts['full'] == null ? null : tr('bidhaa :n', {'n': counts['full']})),
    ];
    final ok = _scope != 'category' || _aisles.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .86),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const T('Hesabu ipi?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 2),
            const T('Si lazima kuhesabu kila kitu mara moja. Mauzo yanaendelea; zisizohesabiwa hazibadiliki.', style: TextStyle(fontSize: 12.5, color: _muted)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final o in options) ...[
                  Pressable(
                    onTap: () {
                      tick();
                      setState(() => _scope = o.$1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _scope == o.$1 ? const Color(0xFFE7F6EF) : const Color(0xFFF5F8F7),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _scope == o.$1 ? _deep : Colors.transparent, width: 1.5),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: _scope == o.$1 ? _deep : Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: Icon(o.$2, size: 20, color: _scope == o.$1 ? Colors.white : _ink),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(o.$3, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))),
                              if (o.$5 != null) Text(o.$5!, style: const TextStyle(fontSize: 12, color: _muted)),
                            ]),
                            const SizedBox(height: 2),
                            Text(o.$4, style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.3)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  if (o.$1 == 'category' && _scope == 'category')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final a in aisles)
                          FilterChip(
                            selected: _aisles.contains(asInt(a['id'])),
                            onSelected: (v) => setState(() => v ? _aisles.add(asInt(a['id'])) : _aisles.remove(asInt(a['id']))),
                            label: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text('${a['name']} · ${a['products']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(_ago(a['last_counted_at'] as String?), style: const TextStyle(fontSize: 11, color: _muted)),
                            ]),
                          ),
                      ]),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: _deep),
              onPressed: ok ? () => Navigator.of(context).pop({'scope': _scope, if (_scope == 'category') 'ids': _aisles.toList()}) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const T('Anza kuhesabu', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}
