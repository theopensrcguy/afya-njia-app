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

const _statusLabels = {
  'pending': ('Inasubiri', warnAmber, Color(0xFFFBEFD6)),
  'received': ('Imepokelewa', brandGreen, Color(0xFFDDF3EA)),
  'rejected': ('Imekataliwa', dangerRed, Color(0xFFFDE7E4)),
};

/// Deliveries. Owner: the ones waiting for confirmation (stock not counted
/// yet). Helper: his own, so he sees whether the owner accepted them.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.session});

  final Session session;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  /// Whoever may confirm sees the waiting ones; others see their own.
  bool get _canConfirm => widget.session.user!.can(Perm.confirmDeliveries);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.session.api.get('purchases', query: {if (_canConfirm) 'status': 'pending'}) as List;
      if (mounted) setState(() => _items = data.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseReviewScreen(session: widget.session, purchase: p)),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_canConfirm ? 'Mizigo ya kuthibitisha' : 'Mizigo yangu'), backgroundColor: pageBackground),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                  if (_items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(_canConfirm ? 'Hakuna mzigo unaosubiri.' : 'Bado hujarekodi mzigo.',
                          textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
                    ),
                  for (final p in _items) _card(p),
                ],
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final (label, fg, bg) = _statusLabels[p['status']] ?? ('${p['status']}', mutedText, mintSoft);
    final at = parseDate(p['received_at']);
    final lines = (p['lines'] as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(p),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(p['supplier'] as Map?)?['name'] ?? 'Msambazaji hajulikani'} · bidhaa ${lines.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${p['received_by'] ?? ''} · ${at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}'}',
                      style: const TextStyle(fontSize: 12, color: mutedText)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatTsh(asInt(p['total_cost'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One delivery in full. For the owner, a pending one ends with
/// Kataa (reason required) / Thibitisha (stock goes up now).
class PurchaseReviewScreen extends StatefulWidget {
  const PurchaseReviewScreen({super.key, required this.session, required this.purchase});

  final Session session;
  final Map<String, dynamic> purchase;

  @override
  State<PurchaseReviewScreen> createState() => _PurchaseReviewScreenState();
}

class _PurchaseReviewScreenState extends State<PurchaseReviewScreen> {
  late Map<String, dynamic> _p = widget.purchase;
  Future<dynamic>? _photo;
  bool _busy = false;

  ApiClient get _api => widget.session.api;
  bool get _canConfirm => widget.session.user!.can(Perm.confirmDeliveries);

  /// Four eyes: nobody confirms a delivery they recorded (the server refuses too).
  bool get _mine => asInt(_p['received_by_id']) == widget.session.user!.id;

  bool get _canPrice => widget.session.user!.can(Perm.editPrices);

  // ---- products this delivery brings for the first time
  final Map<String, TextEditingController> _priceFields = {}; // "productId:unit"
  final Map<int, TextEditingController> _nameFields = {}; // off-catalogue names, editable

  List<Map<String, dynamic>> get _newProducts =>
      ((_p['new_products'] as List?) ?? const []).cast<Map<String, dynamic>>().where((n) => n['is_active'] != true).toList();

  TextEditingController _price(int id, String unit) => _priceFields.putIfAbsent('$id:$unit', TextEditingController.new);

  /// New products still without a price for every unit: Thibitisha waits for them.
  int get _unpriced => _newProducts.where((n) {
        if (n['needs_price'] != true) return false;
        final units = ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
        return units.any((u) => (int.tryParse(_price(asInt(n['id']), '${u['name']}').text.trim()) ?? 0) < 1);
      }).length;

  /// What this delivery paid per base unit for a product (for the profit hint).
  int? _unitCost(int productId) {
    for (final l in ((_p['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      if (asInt(l['product_id']) == productId && l['unit_cost'] != null) return asInt(l['unit_cost']);
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in [..._priceFields.values, ..._nameFields.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The photo is private on the server: fetched with the token, owner only.
    if (_canConfirm && _p['has_photo'] == true) _photo = _api.getBytes('purchases/${_p['id']}/photo');
  }

  Future<void> _decide(bool accept) async {
    String? reason;
    if (!accept) {
      reason = await askText(context,
          title: 'Kataa mzigo', label: 'Sababu', hint: 'mfano: bei hailingani na ankara', required: true, danger: true, confirm: 'Kataa');
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> body = accept
          ? {
              if (_newProducts.isNotEmpty)
                'products': [
                  for (final n in _newProducts)
                    {
                      'id': asInt(n['id']),
                      if (_nameFields[asInt(n['id'])] != null) 'name': _nameFields[asInt(n['id'])]!.text.trim(),
                      'prices': {
                        for (final u in ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>())
                          if ((int.tryParse(_price(asInt(n['id']), '${u['name']}').text.trim()) ?? 0) >= 1)
                            '${u['name']}': int.parse(_price(asInt(n['id']), '${u['name']}').text.trim()),
                      },
                    },
                ],
            }
          : {'reason': ?reason};
      final res = await _api.post('purchases/${_p['id']}/${accept ? 'confirm' : 'reject'}', body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _p = res);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Imethibitishwa. Hisa imeongezeka.' : 'Mzigo umekataliwa.'),
      ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerRed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _p['status'] == 'pending';
    final (label, fg, bg) = _statusLabels[_p['status']] ?? ('${_p['status']}', mutedText, mintSoft);
    final at = parseDate(_p['received_at']);
    final lines = ((_p['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final invoiceTotal = _p['invoice_total'] == null ? null : asInt(_p['invoice_total']);
    final total = asInt(_p['total_cost']);

    return Scaffold(
      appBar: AppBar(title: const Text('Mzigo'), backgroundColor: pageBackground),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 22),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  _kv('Imerekodiwa na', '${_p['received_by'] ?? ''} · ${at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}'}'),
                  _kv('Msambazaji', '${(_p['supplier'] as Map?)?['name'] ?? '—'}'),
                  _kv('Ankara', '${_p['invoice_number'] ?? '—'}'),
                  if (_p['confirmed_by'] != null) _kv(_p['status'] == 'rejected' ? 'Imekataliwa na' : 'Imethibitishwa na', '${_p['confirmed_by']}'),
                  if (_p['rejected_reason'] != null) _kv('Sababu', '${_p['rejected_reason']}'),
                ]),
              ),
              if (_photo != null) _photoThumb(),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: softCard(radius: 22),
            child: Column(children: [
              for (var i = 0; i < lines.length; i++) _line(lines[i], last: i == lines.length - 1),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Jumla ya mzigo', style: TextStyle(color: mutedText))),
                Text(formatTsh(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              if (invoiceTotal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    invoiceTotal == total
                        ? '✓ Inalingana na ankara (${formatTsh(invoiceTotal)})'
                        : 'Ankara inasema ${formatTsh(invoiceTotal)}: tofauti ${formatTsh((invoiceTotal - total).abs())}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: invoiceTotal == total ? brandGreen : dangerRed),
                  ),
                ),
            ]),
          ),
          if (_canConfirm && pending && !_mine)
            for (final n in _newProducts) _newProductCard(n),
          if (_canConfirm && pending && _mine)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Huu ni mzigo uliourekodi mwenyewe: mtu mwingine ndiye athibitishe.',
                  textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
            ),
          if (_canConfirm && pending && !_mine) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: dangerRed,
                    side: const BorderSide(color: dangerRed, width: 2),
                  ),
                  child: const Text('Kataa'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  // A product without a price would reach the counter and sell for nothing.
                  onPressed: _busy || _unpriced > 0 ? null : () => _decide(true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_busy ? 'Inatuma…' : 'Thibitisha mzigo'),
                ),
              ),
            ]),
            if (_unpriced > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _canPrice ? 'Weka bei ya bidhaa mpya $_unpriced kwanza.' : 'Mzigo huu una bidhaa mpya bila bei: anayeweza kuweka bei athibitishe.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: warnAmber, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// One product arriving for the first time: its name (editable if typed by
  /// hand), and a price per unit when it has none yet, with the profit live.
  Widget _newProductCard(Map<String, dynamic> n) {
    final id = asInt(n['id']);
    final units = ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final offCatalogue = n['off_catalogue'] == true;
    final needsPrice = n['needs_price'] == true;
    final cost = _unitCost(id);
    if (offCatalogue) _nameFields.putIfAbsent(id, () => TextEditingController(text: '${n['name']}'));
    Widget badge(String t, Color fg, Color bg) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
        );
    final missing = needsPrice && units.any((u) => (int.tryParse(_price(id, '${u['name']}').text.trim()) ?? 0) < 1);

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: missing ? const Color(0xFFE0A93B) : Colors.transparent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          badge('BIDHAA MPYA', brandGreen, const Color(0xFFDDF3EA)),
          if (offCatalogue) badge('nje ya katalogi', warnAmber, const Color(0xFFFBEFD6)),
        ]),
        const SizedBox(height: 8),
        if (offCatalogue) ...[
          TextField(
            controller: _nameFields[id],
            decoration: const InputDecoration(labelText: 'Jina (limeandikwa na msaidizi: liangalie)'),
          ),
        ] else
          Text('${n['name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        if (needsPrice && !_canPrice)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Haina bei bado. Huna ruhusa ya kuweka bei.', style: TextStyle(color: warnAmber)),
          ),
        if (_canPrice)
          for (final u in units)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _price(id, '${u['name']}'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '${needsPrice ? 'Bei ya kuuza' : 'Bei (si lazima kubadilisha)'}: '
                      '${unitLabel('${u['name']}')}${asInt(u['base_quantity']) > 1 ? ' (${asInt(u['base_quantity'])})' : ''}',
                  hintText: needsPrice ? null : formatTsh(asInt(u['price'])),
                  helperText: _profit(cost, asInt(u['base_quantity']), int.tryParse(_price(id, '${u['name']}').text.trim())),
                ),
              ),
            ),
      ]),
    );
  }

  /// "unanunua TSh 35 · faida 50%"
  String? _profit(int? costPerBase, int size, int? price) {
    if (costPerBase == null || !widget.session.user!.can(Perm.viewCosts)) return null;
    final cost = costPerBase * size;
    if (price == null || price < 1) return 'Unanunua ${formatTsh(cost)}';
    final pct = ((price - cost) * 100 / price).round();
    return 'Unanunua ${formatTsh(cost)} · ${pct < 0 ? 'HASARA' : 'faida $pct%'}';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: mutedText)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _photoThumb() {
    return FutureBuilder<dynamic>(
      future: _photo,
      builder: (context, snap) {
        final bytes = snap.data;
        return GestureDetector(
          onTap: bytes == null
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (d) => Dialog(
                      insetPadding: const EdgeInsets.all(8),
                      child: InteractiveViewer(child: Image.memory(bytes)), // pinch to zoom the invoice
                    ),
                  ),
          child: Container(
            width: 96,
            height: 124,
            decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover)
                : Center(
                    child: snap.hasError
                        ? const Icon(Icons.broken_image_outlined, color: mutedText)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
      },
    );
  }

  Widget _line(Map<String, dynamic> l, {required bool last}) {
    final packName = l['pack_name'] as String?;
    final size = asInt(l['pack_size']);
    final packs = asInt(l['packs']);
    final expiry = parseDate(l['expiry_date']);
    final pack = size == 1 || packName == null ? '$packs' : '$packs ${unitLabel(packName, packs)} × $size = ${asInt(l['quantity'])}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${l['product']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(formatTsh(asInt(l['line_total'])), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Text(
          '$pack · ${l['batch_number']} · inaisha ${expiry == null ? '' : '${expiry.month.toString().padLeft(2, '0')}/${expiry.year}'}'
          ' · ${formatTsh(asInt(l['pack_cost']))} kila moja',
          style: const TextStyle(fontSize: 12, color: mutedText),
        ),
      ]),
    );
  }
}
