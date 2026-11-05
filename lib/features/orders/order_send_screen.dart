import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../suppliers/supplier_form.dart';
import '../suppliers/suppliers_screen.dart';

/// The order as the supplier will read it, then one tap to WhatsApp.
///
/// The order is saved BEFORE WhatsApp opens: from then on it counts as "on
/// its way" (not suggested again), and the next delivery from this supplier
/// closes it. No prices in the message: the supplier's invoice has them.
class OrderSendScreen extends StatefulWidget {
  const OrderSendScreen({
    super.key,
    required this.session,
    required this.supplier,
    this.suppliers = const [],
    required this.cover,
    required this.lines,
  });

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
  bool _busy = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  /// The same wording the server saves; the shop's name is added at the end.
  String? get _phone => (_supplier?['whatsapp_number'] ?? _supplier?['phone']) as String?;

  String get _preview {
    final s = _supplier;
    final rows = [
      for (var i = 0; i < widget.lines.length; i++)
        '${i + 1}. ${widget.lines[i]['name']}: ${widget.lines[i]['pack_name']} ${widget.lines[i]['packs']}',
    ];
    return 'Habari${s != null ? ' ${s['name']}' : ''},\nNaomba mzigo huu:\n\n${rows.join('\n')}\n\nAsante.';
  }

  /// The supplier's details (WhatsApp number, phone, location...), saved for next time.
  Future<void> _editSupplier() async {
    final s = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: _api, initial: _supplier)));
    if (s != null && mounted) setState(() => _supplier = s);
  }

  /// Save the order, then hand its message to WhatsApp (or the clipboard).
  Future<void> _send({required bool whatsapp}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await _api.post('purchase-orders', {
        'supplier_id': ?_supplier?['id'],
        'cover_days': widget.cover,
        'lines': [
          for (final l in widget.lines)
            {
              'product_id': asInt(l['product_id']),
              'pack_name': l['pack_name'],
              'pack_size': asInt(l['pack_size']),
              'packs': asInt(l['packs']),
              'suggested_packs': asInt(l['suggested_packs']),
            },
        ],
      }) as Map<String, dynamic>;
      final message = '${order['message']}';
      if (!mounted) return;

      if (whatsapp) {
        final n = tzNumber(_phone);
        // With a number: straight to that chat. Without: WhatsApp asks whom to send to.
        final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(message)}');
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) {
          await Clipboard.setData(ClipboardData(text: message));
          if (mounted) _toast('WhatsApp haikufunguka. Ujumbe umenakiliwa: ubandike mwenyewe.');
        }
      } else {
        await Clipboard.setData(ClipboardData(text: message));
        _toast('Ujumbe umenakiliwa.');
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
          Text(s == null ? 'Agizo' : 'Agizo · ${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const Text('Angalia, kisha tuma', style: TextStyle(fontSize: 12, color: mutedText)),
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
              child: Text('Jina la duka linaongezwa mwishoni. Bei hazitumwi: msambazaji ataleta ankara.',
                  style: TextStyle(fontSize: 12, color: mutedText)),
            ),
            // No supplier yet: choose one, so the order can close when they deliver.
            if (widget.supplier == null && widget.suppliers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text('Unamtumia nani?', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  title: const Text('Namba ya WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_phone?.isNotEmpty == true ? _phone! : 'Haijawekwa: WhatsApp itakuuliza umtumie nani'),
                  trailing: TextButton(onPressed: _editSupplier, child: Text(_phone?.isNotEmpty == true ? 'Badilisha' : 'Weka')),
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
                onPressed: _busy ? null : () => _send(whatsapp: true),
                icon: const Icon(Icons.chat_rounded),
                label: Text(_busy ? 'Inahifadhi…' : 'Fungua WhatsApp na tuma'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _send(whatsapp: false),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Nakili ujumbe (SMS au simu)'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
