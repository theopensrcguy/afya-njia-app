import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';

/// "Uhamisho mpya": which shop, which products and how many. An approver's
/// transfer leaves at once; anyone else's waits for the owner's approval.
class NewTransferScreen extends StatefulWidget {
  const NewTransferScreen({super.key, required this.session, required this.partners, required this.canApprove});

  final Session session;
  final List<Map<String, dynamic>> partners;
  final bool canApprove;

  @override
  State<NewTransferScreen> createState() => _NewTransferScreenState();
}

class _Line {
  _Line(this.product) : unit = (product.units.toList()..sort((a, b) => b.baseQuantity.compareTo(a.baseQuantity))).first;
  final Product product;
  ProductUnit unit;
  int count = 1;
  int get base => count * unit.baseQuantity;
}

class _NewTransferScreenState extends State<NewTransferScreen> {
  late int _to = (widget.partners.first['id'] as num).toInt();
  final _lines = <_Line>[];
  final _note = TextEditingController();
  final _q = TextEditingController();
  List<Product> _found = [];
  Timer? _debounce;
  bool _busy = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void dispose() {
    _note.dispose();
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _found = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _api.get('products', query: {'q': q.trim()}) as List;
        if (mounted) setState(() => _found = r.cast<Map<String, dynamic>>().map(Product.fromJson).where((p) => p.units.isNotEmpty).toList());
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  void _add(Product p) {
    setState(() {
      if (!_lines.any((l) => l.product.id == p.id)) _lines.add(_Line(p));
      _q.clear();
      _found = [];
    });
  }

  Future<void> _send() async {
    final items = [for (final l in _lines) if (l.base > 0) {'product_id': l.product.id, 'quantity': l.base}];
    if (items.isEmpty) return setState(() => _error = tr('Ongeza angalau bidhaa moja.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.post('transfers', {'to_pharmacy_id': _to, 'items': items, 'note': _note.text.trim().isEmpty ? null : _note.text.trim()}) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['status'] == 'sent' ? tr('Hisa imetumwa. Wakithibitisha, itaingia kwao.') : tr('Uhamisho umeandaliwa. Unasubiri idhini ya mmiliki.')),
      ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Uhamisho mpya', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        DropdownButtonFormField<int>(
          initialValue: _to,
          decoration: InputDecoration(labelText: tr('Kwenda:')),
          items: [
            for (final p in widget.partners)
              DropdownMenuItem(value: (p['id'] as num).toInt(), child: Text('${p['name']}${p['location'] == null ? '' : ' (${p['location']})'}')),
          ],
          onChanged: (v) => setState(() => _to = v ?? _to),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _q,
          onChanged: _search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Ongeza bidhaa: andika jina…')),
        ),
        for (final p in _found)
          ListTile(
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Hisa yako: :n', {'n': describeStock(p.onHand, p.units)})),
            trailing: const Icon(Icons.add_circle, color: brandGreen),
            onTap: () => _add(p),
          ),
        const SizedBox(height: 12),
        if (_lines.isEmpty) const T('Ongeza bidhaa kwa kutafuta juu.', style: TextStyle(color: mutedText)),
        for (final l in _lines) _lineCard(l),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLength: 255, decoration: InputDecoration(labelText: tr('Maelezo (si lazima): mfano kwa ajili ya wiki hii'))),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        T(widget.canApprove ? 'Ukituma, hisa inatoka sasa hivi (wewe ni mwenye idhini).' : 'Itasubiri idhini ya mmiliki kabla hisa haijatoka.',
            style: const TextStyle(fontSize: 12, color: mutedText)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy || _lines.isEmpty ? null : _send,
          icon: const Icon(Icons.send_rounded),
          label: T(widget.canApprove ? 'Tuma hisa' : 'Tuma kwa idhini'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ]),
    );
  }

  Widget _lineCard(_Line l) {
    final units = l.product.units.toList()..sort((a, b) => b.baseQuantity.compareTo(a.baseQuantity));
    final tooMuch = l.base > l.product.onHand;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: softCard(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(tooltip: tr('Ondoa'), onPressed: () => setState(() => _lines.remove(l)), icon: const Icon(Icons.close, size: 20)),
        ]),
        Text(tr('Hisa yako: :n', {'n': describeStock(l.product.onHand, l.product.units)}),
            style: TextStyle(fontSize: 12, color: tooMuch ? dangerRed : mutedText)),
        const SizedBox(height: 6),
        // The amount and its unit side by side.
        Row(children: [
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: '${l.count}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) => setState(() => l.count = int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(spacing: 6, children: [
              for (final u in units)
                ChoiceChip(
                  label: Text(u.baseQuantity > 1 ? '${u.name} (${u.baseQuantity})' : u.name),
                  selected: l.unit.name == u.name,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => l.unit = u),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}
