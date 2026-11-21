import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
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

  /// Section label: "1 · Kwenda duka gani?"
  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text('$n · ${tr(text)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedText)),
      );

  @override
  Widget build(BuildContext context) {
    final items = _lines.where((l) => l.base > 0).length;
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Uhamisho mpya', style: TextStyle(fontWeight: FontWeight.w800))),
      // v0.48.2: the send bar stays under the thumb; the shop is a card (the dropdown overflowed with long names).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Bidhaa :n', {'n': items}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  T(widget.canApprove ? 'Inatoka sasa (unaidhinisha wewe)' : 'Itasubiri idhini ya mmiliki',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB7D3C9), fontSize: 11.5)),
                ]),
              ),
              FilledButton.icon(
                onPressed: _busy || items == 0 ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: T(widget.canApprove ? 'Tuma' : 'Tuma kwa idhini'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3DDC97),
                  foregroundColor: const Color(0xFF0E3B31),
                  disabledBackgroundColor: Colors.white12,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                ),
              ),
            ]),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        _step('1', 'Kwenda duka gani?'),
        LayoutBuilder(builder: (context, box) {
          final w = widget.partners.length == 1 ? box.maxWidth : (box.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in widget.partners)
              SizedBox(
                width: w,
                child: Pressable(
                  onTap: () => setState(() => _to = (p['id'] as num).toInt()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _to == (p['id'] as num).toInt() ? brandGreen : Colors.transparent, width: 1.6),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (p['location'] != null)
                            Text('${p['location']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: mutedText)),
                        ]),
                      ),
                      if (_to == (p['id'] as num).toInt()) const Icon(Icons.check_circle_rounded, color: brandGreen, size: 20),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
        _step('2', 'Bidhaa gani?'),
        TextField(
          controller: _q,
          onChanged: _search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tafuta bidhaa…'), filled: true, fillColor: Colors.white),
        ),
        if (_found.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (final p in _found)
                ListTile(
                  dense: true,
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Hisa yako: :n', {'n': describeStock(p.onHand, p.units)})),
                  trailing: const Icon(Icons.add_circle_rounded, color: brandGreen),
                  onTap: () => _add(p),
                ),
            ]),
          ),
        const SizedBox(height: 8),
        if (_lines.isEmpty) const Padding(padding: EdgeInsets.all(8), child: T('Tafuta, kisha gusa bidhaa kuiongeza.', style: TextStyle(color: mutedText))),
        for (final l in _lines) _lineCard(l),
        _step('3', 'Ujumbe (si lazima)'),
        TextField(
          controller: _note,
          maxLength: 255,
          decoration: InputDecoration(hintText: tr('mfano: kwa ajili ya wiki hii'), filled: true, fillColor: Colors.white, counterText: ''),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
      ]),
    );
  }

  Widget _lineCard(_Line l) {
    final units = l.product.units.toList()..sort((a, b) => b.baseQuantity.compareTo(a.baseQuantity));
    final tooMuch = l.base > l.product.onHand;
    Widget b(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: onTap == null ? const Color(0xFFC5D2CD) : brandGreen)),
        );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(tr('Hisa yako: :n', {'n': describeStock(l.product.onHand, l.product.units)}),
                  style: TextStyle(fontSize: 12, color: tooMuch ? dangerRed : mutedText, fontWeight: tooMuch ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              b(Icons.remove_rounded, l.count > 1 ? () => setState(() => l.count--) : null),
              InkWell(
                onTap: () async {
                  final v = await askText(context, title: tr('Idadi'), label: unitLabel(l.unit.name), initial: '${l.count}', digitsOnly: true, required: true);
                  final k = int.tryParse(v ?? '');
                  if (k != null && k > 0) setState(() => l.count = k);
                },
                child: SizedBox(width: 38, child: Text('${l.count}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, decoration: TextDecoration.underline, decorationColor: Color(0xFFC5D2CD)))),
              ),
              b(Icons.add_rounded, () => setState(() => l.count++)),
            ]),
          ),
          const SizedBox(width: 6),
          Pressable(
            onTap: () => setState(() => _lines.remove(l)),
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: dangerSoft, shape: BoxShape.circle),
              child: Icon(Icons.close_rounded, size: 16, color: dangerRed.withValues(alpha: 0.85), semanticLabel: tr('Ondoa')),
            ),
          ),
        ]),
        if (units.length > 1) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final u in units)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(u.baseQuantity > 1 ? '${unitLabel(u.name)} (${u.baseQuantity})' : unitLabel(u.name)),
                selected: l.unit.name == u.name,
                showCheckmark: false,
                onSelected: (_) => setState(() => l.unit = u),
              ),
          ]),
        ],
      ]),
    );
  }
}
