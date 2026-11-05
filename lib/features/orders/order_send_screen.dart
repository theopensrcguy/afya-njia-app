import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/session.dart';

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
    required this.cover,
    required this.lines,
  });

  final Session session;
  final Map<String, dynamic>? supplier;
  final int cover;

  /// Reorder lines with the chosen 'packs'.
  final List<Map<String, dynamic>> lines;

  @override
  State<OrderSendScreen> createState() => _OrderSendScreenState();
}

class _OrderSendScreenState extends State<OrderSendScreen> {
  late String? _phone = (widget.supplier?['phone'] as String?)?.trim();
  bool _busy = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  /// The same wording the server saves; the shop's name is added at the end.
  String get _preview {
    final s = widget.supplier;
    final rows = [
      for (var i = 0; i < widget.lines.length; i++)
        '${i + 1}. ${widget.lines[i]['name']}: ${widget.lines[i]['pack_name']} ${widget.lines[i]['packs']}',
    ];
    return 'Habari${s != null ? ' ${s['name']}' : ''},\nNaomba mzigo huu:\n\n${rows.join('\n')}\n\nAsante.';
  }

  /// "0712 345 678" or "+255 712..." → "255712345678", what wa.me wants.
  static String? waNumber(String? phone) {
    final d = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('0')) return '255${d.substring(1)}';
    if (d.length == 9) return '255$d';
    return d;
  }

  Future<void> _editPhone() async {
    final s = widget.supplier;
    if (s == null) return;
    final v = await askText(context,
        title: 'Namba ya WhatsApp ya ${s['name']}', label: 'Namba ya simu', hint: '0712 345 678', initial: _phone ?? '');
    if (v == null || !mounted) return;
    try {
      final res = await _api.patch('suppliers/${s['id']}', {'phone': v.trim()}) as Map<String, dynamic>;
      if (mounted) setState(() => _phone = res['phone'] as String?);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Save the order, then hand its message to WhatsApp (or the clipboard).
  Future<void> _send({required bool whatsapp}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await _api.post('purchase-orders', {
        'supplier_id': ?widget.supplier?['id'],
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
        final n = waNumber(_phone);
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
    final s = widget.supplier;
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
            if (s != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                decoration: softCard(radius: 18),
                child: ListTile(
                  title: const Text('Namba ya WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_phone?.isNotEmpty == true ? _phone! : 'Haijawekwa: WhatsApp itakuuliza umtumie nani'),
                  trailing: TextButton(onPressed: _editPhone, child: Text(_phone?.isNotEmpty == true ? 'Badilisha' : 'Weka')),
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
