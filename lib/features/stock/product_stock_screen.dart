import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'units_editor_screen.dart';

/// One product: what's on the shelf, how it's sold, its batches, and every
/// change to its stock (who, when, why). Owner only.
///
/// The history answers "where did the 20 tablets go?": it is read from the
/// stock ledger, which can only be added to, never edited.
class ProductStockScreen extends StatefulWidget {
  const ProductStockScreen({super.key, required this.session, required this.productId, required this.name});

  final Session session;
  final int productId;
  final String name;

  @override
  State<ProductStockScreen> createState() => _ProductStockScreenState();
}

class _ProductStockScreenState extends State<ProductStockScreen> {
  Map<String, dynamic>? _p;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool _can(String p) => widget.session.user!.can(p);

  List<ProductUnit> get _units =>
      (((_p ?? const {})['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final p = await _api.get('stock/${widget.productId}') as Map<String, dynamic>;
      if (mounted) setState(() => _p = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  // ------------------------------------------------------------------ edits

  Future<void> _editReorderLevel() async {
    final units = _units;
    final base = units.isEmpty ? '' : unitLabel(units.first.name, 2);
    final answer = await askText(
      context,
      title: 'Kiwango cha kuagiza',
      message: 'Hisa ikifika hapa au chini, bidhaa itaonekana kwenye "za kuagiza".',
      label: 'Idadi ($base)',
      helper: units.length > 1 ? '${unitLabel(units[1].name)} 1 = ${units[1].baseQuantity} $base' : null,
      initial: '${asInt(_p!['reorder_level'])}',
      digitsOnly: true,
      required: true,
    );
    if (answer == null) return;
    try {
      await _api.patch('products/${widget.productId}', {'reorder_level': int.parse(answer)});
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _editUnits() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => UnitsEditorScreen(api: _api, productId: widget.productId, name: widget.name, units: _units),
    ));
    if (saved == true) _load();
  }

  /// Remove stock that isn't on the shelf any more: damaged, lost, expired,
  /// returned. Always with a reason; the owner sees it in the history.
  Future<void> _adjust() async {
    final batches = ((_p!['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (batches.isEmpty) {
      _toast('Hakuna batch yenye hisa ya kurekebisha.');
      return;
    }
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (_) => _AdjustSheet(api: _api, batches: batches, units: _units),
    );
    if (done == true) {
      _toast('Hisa imerekebishwa.');
      _load();
    }
  }

  // ----------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), backgroundColor: pageBackground),
      body: _p == null
          ? Center(
              child: _error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: dangerRed)),
                      TextButton(onPressed: _load, child: const Text('Jaribu tena')),
                    ])
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  _onHandCard(),
                  const SizedBox(height: 14),
                  _unitsCard(),
                  const SizedBox(height: 14),
                  _priceHistoryCard(),
                  const SizedBox(height: 14),
                  _batchesCard(),
                  const SizedBox(height: 14),
                  _historyCard(),
                  const SizedBox(height: 16),
                  if (_can(Perm.adjustStock))
                  OutlinedButton.icon(
                    onPressed: _adjust,
                    icon: const Icon(Icons.tune),
                    label: const Text('Rekebisha hisa (imeharibika, imepotea…)'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: cardColor),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: softCard(radius: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _onHandCard() {
    final p = _p!;
    final units = _units;
    final onHand = asInt(p['on_hand']);
    final reorder = asInt(p['reorder_level']);
    final low = onHand <= reorder;
    final progress = reorder == 0 ? 1.0 : (onHand / (reorder * 2)).clamp(0.0, 1.0);

    return _card(children: [
      Row(children: [
        const Expanded(child: Text('Iliyopo sasa', style: TextStyle(color: mutedText))),
        if (onHand == 0)
          _badge('Hazipo', dangerRed, const Color(0xFFFDE7E4))
        else if (low)
          _badge('Chache · agiza', warnAmber, const Color(0xFFFBEFD6)),
      ]),
      const SizedBox(height: 4),
      Text(describeStock(onHand, units), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
      Text('Jumla ${unitLabel(units.isEmpty ? '' : units.first.name, 2)} $onHand'
          '${_can(Perm.viewCosts) ? ' · thamani ${formatTsh(asInt(p['value_at_cost']))}' : ''}',
          style: const TextStyle(color: mutedText, fontSize: 13)),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          backgroundColor: mintSoft,
          color: low ? const Color(0xFFE0A93B) : mintAccent,
        ),
      ),
      const SizedBox(height: 6),
      InkWell(
        onTap: _can(Perm.editPrices) ? _editReorderLevel : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text('Kiwango cha kuagiza: ${describeStock(reorder, units)}',
                  style: const TextStyle(fontSize: 13, color: mutedText)),
            ),
            if (_can(Perm.editPrices)) const Icon(Icons.edit_outlined, size: 18, color: mutedText),
          ]),
        ),
      ),
    ]);
  }

  Widget _badge(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _unitsCard() {
    final units = _units;
    final lastCost = _p!['last_unit_cost'];
    return _card(children: [
      Row(children: [
        const Expanded(child: Text('Vipimo na bei', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        if (_can(Perm.editPrices))
          TextButton.icon(onPressed: _editUnits, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Badilisha')),
      ]),
      // Selling price against buying price, per unit. The cost is the last
      // delivery's cost × the unit's size; a red margin means selling at a loss.
      for (final raw in ((_p!['units'] as List?) ?? const []).cast<Map<String, dynamic>>())
        Builder(builder: (_) {
          final u = ProductUnit.fromJson(raw);
          final margin = raw['margin_percent'] as int?;
          final losing = margin != null && margin <= 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  u.baseQuantity == 1
                      ? unitLabel(u.name)
                      : '${unitLabel(u.name)} (${unitLabel(units.first.name, u.baseQuantity)} ${u.baseQuantity})',
                  style: const TextStyle(color: mutedText),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatTsh(u.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                if (margin != null)
                  Text(
                    losing ? 'Hasara! gharama ${formatTsh(asInt(raw['cost']))}' : 'Faida $margin% · gharama ${formatTsh(asInt(raw['cost']))}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: losing ? dangerRed : brandGreen),
                  ),
              ]),
            ]),
          );
        }),
      if (lastCost != null) ...[
        const Divider(height: 20),
        Row(children: [
          const Expanded(child: Text('Bei ya kununua (mwisho)', style: TextStyle(color: mutedText))),
          Text('${formatTsh(asInt(lastCost))} / ${unitLabel(units.isEmpty ? '' : units.first.name)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ],
    ]);
  }

  /// Every selling-price change, newest first: when, by whom, from what to what.
  Widget _priceHistoryCard() {
    final history = ((_p!['price_history'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (history.isEmpty) return const SizedBox.shrink();
    return _card(children: [
      const Text('Historia ya bei', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      for (final h in history.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(unitLabel('${h['unit']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_whenWho(h), style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            Text(_priceChange(h), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
    ]);
  }

  String _whenWho(Map<String, dynamic> h) {
    final at = parseDate(h['at']);
    final when = at == null ? '' : swahiliDate(at.toLocal());
    return h['user'] == null ? '$when · bei ya kuanzia' : '$when · ${h['user']}';
  }

  String _priceChange(Map<String, dynamic> h) {
    final old = h['old_price'];
    final now = h['new_price'];
    if (old == null) return formatTsh(asInt(now));
    if (now == null) return 'kimeondolewa';
    final diff = asInt(now) - asInt(old);
    final pct = asInt(old) == 0 ? 0 : (diff * 100 / asInt(old)).round();
    return '${formatTsh(asInt(old))} → ${formatTsh(asInt(now))} (${pct >= 0 ? '+' : ''}$pct%)';
  }

  Widget _batchesCard() {
    final units = _units;
    final batches = ((_p!['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return _card(children: [
      const Text('Batch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const Text('Inayoisha kwanza inauzwa kwanza', style: TextStyle(fontSize: 12, color: mutedText)),
      if (batches.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('Hakuna batch yenye hisa.', style: TextStyle(color: mutedText))),
      for (var i = 0; i < batches.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border: i == batches.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${batches[i]['batch_number']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (batches[i]['selling_now'] == true) ...[
                    const SizedBox(width: 6),
                    _badge('inauzwa sasa', brandGreen, const Color(0xFFDDF3EA)),
                  ],
                ]),
                Text(_expiryText(batches[i]),
                    style: TextStyle(fontSize: 12, color: batches[i]['is_expired'] == true ? dangerRed : mutedText)),
              ]),
            ),
            Text(describeStock(asInt(batches[i]['quantity']), units), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
    ]);
  }

  String _expiryText(Map<String, dynamic> b) {
    final d = parseDate(b['expiry_date']);
    final days = asInt(b['days_left']);
    final date = d == null ? '' : '${d.month.toString().padLeft(2, '0')}/${d.year}';
    if (b['is_expired'] == true) return 'Imeisha muda $date · haiuzwi';
    return days <= 90 ? 'Inaisha $date · siku $days' : 'Inaisha $date';
  }

  static const _types = {
    'purchase': ('Mzigo umepokelewa', '+'),
    'sale': ('Mauzo', '−'),
    'void': ('Mauzo yamefutwa (yamerudi)', '+'),
    'adjustment': ('Marekebisho', '!'),
    'expired': ('Imeisha muda', '!'),
    'return_to_supplier': ('Imerudishwa kwa msambazaji', '!'),
  };

  Widget _historyCard() {
    final units = _units;
    final history = ((_p!['history'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return _card(children: [
      const Text('Historia', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      if (history.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('Bado hakuna mabadiliko.', style: TextStyle(color: mutedText))),
      for (var i = 0; i < history.length; i++) _historyRow(history[i], units, last: i == history.length - 1),
    ]);
  }

  Widget _historyRow(Map<String, dynamic> h, List<ProductUnit> units, {required bool last}) {
    final (label, sign) = _types[h['type']] ?? ('${h['type']}', '!');
    final qty = asInt(h['quantity']);
    final at = parseDate(h['at']);
    final (Color ink, Color tint) = sign == '+'
        ? (brandGreen, const Color(0xFFDDF3EA))
        : sign == '−'
            ? (dangerRed, const Color(0xFFFDE7E4))
            : (warnAmber, const Color(0xFFFBEFD6));
    final note = '${h['note'] ?? ''}'.trim();
    final when = at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
          child: Text(sign, style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.isEmpty ? label : '$label: $note',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('$when · ${h['user'] ?? ''}${h['batch_number'] != null ? ' · ${h['batch_number']}' : ''}',
                style: const TextStyle(fontSize: 12, color: mutedText)),
          ]),
        ),
        Text('${qty > 0 ? '+' : '−'}${describeStock(qty.abs(), units)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
      ]),
    );
  }
}

/// Remove stock from one batch, with a reason.
class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.api, required this.batches, required this.units});

  final ApiClient api;
  final List<Map<String, dynamic>> batches;
  final List<ProductUnit> units;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  static const _reasons = [
    ('adjustment', 'Imeharibika'),
    ('adjustment', 'Imepotea'),
    ('expired', 'Imeisha muda'),
    ('return_to_supplier', 'Imerudishwa kwa msambazaji'),
  ];

  late Map<String, dynamic> _batch = widget.batches.first;
  int _reason = 0;
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = int.tryParse(_qty.text.trim()) ?? 0;
    if (n <= 0) {
      setState(() => _error = 'Weka idadi ya kuondoa.');
      return;
    }
    if (n > asInt(_batch['quantity'])) {
      setState(() => _error = 'Batch hii ina ${asInt(_batch['quantity'])} tu.');
      return;
    }
    final (type, label) = _reasons[_reason];
    final extra = _note.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('batches/${_batch['id']}/adjust', {
        'delta': -n,
        'type': type,
        'note': extra.isEmpty ? label : '$label: $extra',
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.units.isEmpty ? '' : unitLabel(widget.units.first.name, 2);
    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Rekebisha hisa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Batch', style: TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final b in widget.batches)
              ChoiceChip(
                label: Text('${b['batch_number']} · ${describeStock(asInt(b['quantity']), widget.units)}'),
                selected: identical(b, _batch),
                showCheckmark: false,
                onSelected: (_) => setState(() => _batch = b),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (var i = 0; i < _reasons.length; i++)
              ChoiceChip(
                label: Text(_reasons[i].$2),
                selected: _reason == i,
                showCheckmark: false,
                onSelected: (_) => setState(() => _reason = i),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Idadi ya kuondoa ($base)', errorText: _error),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Maelezo zaidi (si lazima)')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving ? 'Inahifadhi…' : 'Ondoa kwenye hisa'),
          ),
        ],
      ),
    );
  }
}
