import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../suppliers/supplier_form.dart';
import '../suppliers/suppliers_screen.dart';
import '../../core/i18n.dart';

/// The order as the supplier will read it, then one tap to WhatsApp, or
/// "Hifadhi rasimu" to finish it later (a draft doesn't count as ordered).
///
/// The order is saved BEFORE WhatsApp opens: from then on it counts as "on
/// its way" (not suggested again), and the next delivery from this supplier
/// closes it. No prices in the message: the supplier's invoice has them.
/// Amounts can still be changed here (and a draft's, when it is reopened).
class OrderSendScreen extends StatefulWidget {
  const OrderSendScreen({
    super.key,
    required this.session,
    required this.supplier,
    this.suppliers = const [],
    required this.cover,
    required this.lines,
    this.orderId,
    this.draftPart = false,
  });

  /// One supplier's part of the draft [orderId]: sending it makes its own order,
  /// and the rest stays in the draft (no "Hifadhi rasimu" here: it was just saved).
  final bool draftPart;

  /// A draft being finished: saving changes it instead of making a new order.
  final int? orderId;

  final Session session;
  final Map<String, dynamic>? supplier;

  /// To choose one when the list had no supplier yet.
  final List<Map<String, dynamic>> suppliers;
  final int cover;

  /// Reorder lines with the chosen 'packs'.
  final List<Map<String, dynamic>> lines;

  @override
  State<OrderSendScreen> createState() => _OrderSendScreenState();
}

class _OrderSendScreenState extends State<OrderSendScreen> {
  late Map<String, dynamic>? _supplier = widget.supplier;
  late final List<Map<String, dynamic>> _lines = [for (final l in widget.lines) {...l}];
  bool _busy = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  /// The same wording the server saves; the shop's name is added at the end.
  String? get _phone => (_supplier?['whatsapp_number'] ?? _supplier?['phone']) as String?;

  String get _preview {
    final s = _supplier;
    final kept = _kept;
    final rows = [
      for (var i = 0; i < kept.length; i++) '${i + 1}. ${kept[i]['name']}: ${kept[i]['pack_name']} ${kept[i]['packs']}',
    ];
    return tr('Habari:a,\nNaomba mzigo huu:\n\n:b\n\nAsante.', {'a': s != null ? ' ${s['name']}' : '', 'b': rows.join('\n')});
  }

  List<Map<String, dynamic>> get _kept => _lines.where((l) => asInt(l['packs']) > 0).toList();

  Map<String, dynamic> _body({required bool draft}) => {
        'supplier_id': _supplier?['id'],
        'cover_days': widget.cover,
        'draft': draft,
        'lines': [
          for (final l in _kept)
            {
              'product_id': asInt(l['product_id']),
              'pack_name': l['pack_name'],
              'pack_size': asInt(l['pack_size']),
              'packs': asInt(l['packs']),
              if (l['suggested_packs'] != null) 'suggested_packs': asInt(l['suggested_packs']),
            },
        ],
      };

  Future<Map<String, dynamic>> _save({required bool draft}) async {
    if (widget.draftPart) {
      final b = _body(draft: false)..remove('draft')..remove('cover_days');
      return await _api.post('purchase-orders/${widget.orderId}/send', b) as Map<String, dynamic>;
    }
    final body = _body(draft: draft);
    final r = widget.orderId == null ? await _api.post('purchase-orders', body) : await _api.patch('purchase-orders/${widget.orderId}', body);
    return r as Map<String, dynamic>;
  }

  /// Not ready to send: keep it as a draft (rasimu), on the phone and the web.
  Future<void> _saveDraft() async {
    if (_kept.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _save(draft: true);
      if (!mounted) return;
      _toast(tr('Rasimu imehifadhiwa. Itume ukiwa tayari.'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The supplier's details (WhatsApp number, phone, location...), saved for next time.
  Future<void> _editSupplier() async {
    final s = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: _api, initial: _supplier)));
    if (s != null && mounted) setState(() => _supplier = s);
  }

  /// Save the order, then hand its message to WhatsApp (or the clipboard).
  Future<void> _send({required bool whatsapp}) async {
    if (_kept.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await _save(draft: false);
      final message = '${order['message']}';
      if (!mounted) return;

      if (whatsapp) {
        final n = tzNumber(_phone);
        // With a number: straight to that chat. Without: WhatsApp asks whom to send to.
        final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(message)}');
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) {
          await Clipboard.setData(ClipboardData(text: message));
          if (mounted) _toast(tr('WhatsApp haikufunguka. Ujumbe umenakiliwa: ubandike mwenyewe.'));
        }
      } else {
        await Clipboard.setData(ClipboardData(text: message));
        _toast(tr('Ujumbe umenakiliwa.'));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final s = _supplier;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s == null ? tr('Agizo') : tr('Agizo · :a', {'a': s['name']}), style: const TextStyle(fontWeight: FontWeight.w800)),
          T(widget.orderId == null ? 'Angalia, kisha tuma' : 'Rasimu: maliza, kisha tuma', style: const TextStyle(fontSize: 12, color: mutedText)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFDCF5DE),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(_preview, style: const TextStyle(fontSize: 15, height: 1.5)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: T('Jina la duka linaongezwa mwishoni. Bei hazitumwi: msambazaji ataleta ankara.',
                  style: TextStyle(fontSize: 12, color: mutedText)),
            ),
            // Last changes before sending: how many of each (0 = leave it out).
            Container(
              margin: const EdgeInsets.only(top: 16),
              decoration: softCard(radius: 18),
              child: Column(children: [
                for (final l in _lines)
                  ListTile(
                    dense: true,
                    title: Text('${l['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: asInt(l['packs']) > 0 ? inkColor : mutedText)),
                    subtitle: Text('${l['pack_name']}${asInt(l['pack_size']) > 1 ? ' (${l['pack_size']})' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tr('Punguza'),
                        onPressed: asInt(l['packs']) > 0 ? () => setState(() => l['packs'] = asInt(l['packs']) - 1) : null,
                        icon: const Icon(Icons.remove_circle_outline, color: brandGreen),
                      ),
                      SizedBox(width: 34, child: Text('${l['packs']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                      IconButton(
                        tooltip: tr('Ongeza'),
                        onPressed: () => setState(() => l['packs'] = asInt(l['packs']) + 1),
                        icon: const Icon(Icons.add_circle, color: brandGreen),
                      ),
                    ]),
                  ),
              ]),
            ),
            // No supplier yet: choose one, so the order can close when they deliver.
            if ((widget.supplier == null || (widget.orderId != null && !widget.draftPart)) && widget.suppliers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: T('Unamtumia nani?', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final x in widget.suppliers)
                  ChoiceChip(
                    label: Text('${x['name']}'),
                    selected: _supplier?['id'] == x['id'],
                    showCheckmark: false,
                    selectedColor: brandGreen,
                    labelStyle: TextStyle(color: _supplier?['id'] == x['id'] ? Colors.white : inkColor, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() => _supplier = _supplier?['id'] == x['id'] ? null : x),
                  ),
              ]),
            ],
            if (s != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                decoration: softCard(radius: 18),
                child: ListTile(
                  title: const T('Namba ya WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_phone?.isNotEmpty == true ? _phone! : tr('Haijawekwa: WhatsApp itakuuliza umtumie nani')),
                  trailing: TextButton(onPressed: _editSupplier, child: Text(_phone?.isNotEmpty == true ? tr('Badilisha') : tr('Weka'))),
                ),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: dangerRed))),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                onPressed: _busy || _kept.isEmpty ? null : () => _send(whatsapp: true),
                icon: const Icon(Icons.chat_rounded),
                label: Text(_busy ? tr('Inahifadhi…') : tr('Fungua WhatsApp na tuma')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (!widget.draftPart) Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _kept.isEmpty ? null : _saveDraft,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const T('Hifadhi rasimu'),
                  ),
                ),
                if (!widget.draftPart) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _kept.isEmpty ? null : () => _send(whatsapp: false),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const T('Nakili ujumbe', textAlign: TextAlign.center),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
