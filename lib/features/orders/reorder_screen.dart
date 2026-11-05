import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'order_send_screen.dart';

/// Agiza: what will run out before the next delivery, grouped by supplier,
/// in whole packs the way that supplier delivers.
///
/// The numbers come from the shop's own sales and deliveries (the server
/// works them out); the owner only checks, adjusts with − / +, and sends.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  int _cover = 14;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  /// What the person chose, by product id (starts at the suggestion).
  final Map<int, int> _packs = {};

  ApiClient get _api => widget.session.api;
  bool get _costs => widget.session.user!.can(Perm.viewCosts);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.get('reorder', query: {'cover': '$_cover'}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = d;
        _packs.clear(); // new cover = new suggestions
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _groups => ((_data?['groups'] as List?) ?? const []).cast<Map<String, dynamic>>();

  int _chosen(Map<String, dynamic> l) => _packs[asInt(l['product_id'])] ?? asInt(l['suggested_packs']);

  Future<void> _send(Map<String, dynamic> g) async {
    final lines = ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final chosen = [
      for (final l in lines)
        if (_chosen(l) > 0) {...l, 'packs': _chosen(l)},
    ];
    if (chosen.isEmpty) return;
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderSendScreen(
        session: widget.session,
        supplier: g['supplier'] as Map<String, dynamic>?,
        cover: _cover,
        lines: chosen,
      ),
    ));
    if (sent == true && mounted) _load(); // sent items now count as "on its way"
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Agiza', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('Zitakazoisha kabla mzigo ujao haujafika', style: TextStyle(fontSize: 12, color: mutedText)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(children: [
              for (final d in const [7, 14, 30])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: SizedBox(width: double.infinity, child: Text('Kwa siku $d', textAlign: TextAlign.center)),
                      selected: _cover == d,
                      showCheckmark: false,
                      selectedColor: brandGreen,
                      labelStyle: TextStyle(color: _cover == d ? Colors.white : inkColor, fontWeight: FontWeight.w800),
                      onSelected: (_) {
                        setState(() => _cover = d);
                        _load();
                      },
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            if (_loading && _data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: dangerRed))),
            if (!_loading && _error == null && _groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Hakuna kitakachoisha kabla mzigo ujao.', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
              ),
            for (final g in _groups) _group(g),
            if (_groups.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(
                  'Idadi imehesabiwa kutoka mauzo ya siku 30, muda ambao msambazaji huchukua kuleta mzigo, na '
                  'vifungashio anavyoleta. Badilisha ukipenda.',
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _group(Map<String, dynamic> g) {
    final s = g['supplier'] as Map<String, dynamic>?;
    final lines = ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final lastDays = g['last_delivery_days'];
    final lead = asInt(g['lead_days']);
    final note = s == null
        ? 'Hazijawahi kuletwa na msambazaji anayejulikana'
        : '${g['lead_learned'] == true ? 'Huleta kila siku ~$lead' : 'Muda wa kuleta: siku $lead (makadirio)'}'
            '${lastDays != null ? ' · mara ya mwisho siku $lastDays zilizopita' : ''}';
    var total = 0;
    var priced = true;
    for (final l in lines) {
      if (l['pack_cost'] == null) priced = false;
      total += _chosen(l) * asInt(l['pack_cost']);
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: softCard(radius: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s == null ? 'Bila msambazaji' : '${s['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(note, style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            if (_costs && priced && total > 0) Text('~${formatTsh(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
        for (final l in lines) _line(l),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: FilledButton.icon(
            onPressed: lines.any((l) => _chosen(l) > 0) ? () => _send(g) : null,
            icon: const Icon(Icons.send_rounded),
            label: Text(s == null ? 'Andaa ujumbe' : 'Tuma kwa ${s['name']}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ]),
    );
  }

  Widget _line(Map<String, dynamic> l) {
    final id = asInt(l['product_id']);
    final onHand = asInt(l['on_hand']);
    final days = l['days_left'];
    final onOrder = asInt(l['on_order']);
    final units = [for (final u in ((l['units'] as List?) ?? const []).cast<Map<String, dynamic>>()) ProductUnit.fromJson(u)];
    final urgent = onHand == 0 || (days != null && asInt(days) < 2);
    final why = onHand == 0
        ? 'Imeisha'
        : days != null
            ? 'Itaisha baada ya siku $days${asInt(days) < 2 ? '!' : ''} · zipo ${describeStock(onHand, units)}'
            : 'Chini ya kiwango · zipo ${describeStock(onHand, units)}';
    final n = _chosen(l);
    final pack = '${l['pack_name']}';

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE3EDE8)))),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(why, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgent ? dangerRed : warnAmber)),
            if (onOrder > 0)
              Text('Imeshaagizwa: ${describeStock(onOrder, units)}', style: const TextStyle(fontSize: 12, color: mutedText)),
            if (asInt(l['pack_size']) > 1)
              Text('$pack = ${unitLabel(units.isEmpty ? '' : units.first.name, asInt(l['pack_size']))} ${l['pack_size']}',
                  style: const TextStyle(fontSize: 11, color: mutedText)),
          ]),
        ),
        IconButton(
          tooltip: 'Punguza',
          onPressed: n > 0 ? () => setState(() => _packs[id] = n - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: brandGreen),
        ),
        SizedBox(
          width: 70,
          child: Text('$n ${unitLabel(pack, n)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        IconButton(
          tooltip: 'Ongeza',
          onPressed: () => setState(() => _packs[id] = n + 1),
          icon: const Icon(Icons.add_circle, color: brandGreen),
        ),
      ]),
    );
  }
}
