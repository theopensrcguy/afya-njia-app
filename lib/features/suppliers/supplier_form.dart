import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';

/// Add or edit a supplier. Only the name is needed; everything else is
/// filled in when someone has it, and helps later (WhatsApp orders, calls,
/// the TIN that's on their invoices).
/// Returns the saved supplier, as the server sends it.
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({super.key, required this.api, this.initial});

  final ApiClient api;
  final Map<String, dynamic>? initial;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  static const _fields = ['name', 'contact_person', 'phone', 'whatsapp', 'email', 'location', 'tin', 'notes'];
  late final Map<String, TextEditingController> _c = {
    for (final f in _fields) f: TextEditingController(text: '${widget.initial?[f] ?? ''}'),
  };
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_c['name']!.text.trim().isEmpty) {
      setState(() => _fieldErrors = {'name': 'Andika jina'});
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    final body = {for (final f in _fields) f: _c[f]!.text.trim()};
    try {
      final id = widget.initial?['id'];
      final res = id == null
          ? await widget.api.post('suppliers', body)
          : await widget.api.patch('suppliers/$id', body);
      if (mounted) Navigator.of(context).pop(res as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _fieldErrors = {
          for (final entry in ((e.data['errors'] as Map?) ?? const {}).entries)
            entry.key: '${(entry.value as List?)?.first ?? entry.value}',
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {String? hint, String? helper, TextInputType? type, int lines = 1, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          keyboardType: type,
          maxLines: lines,
          textCapitalization: type == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            errorText: _fieldErrors[key],
            prefixIcon: icon == null ? null : Icon(icon),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Text(widget.initial == null ? 'Msambazaji mpya' : 'Taarifa za msambazaji'),
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              _field('name', 'Jina la msambazaji *', icon: Icons.storefront_outlined),
              _field('contact_person', 'Mtu wa kuongea naye', hint: 'mfano: Bw. Juma', icon: Icons.person_outline),
              _field('phone', 'Simu', hint: '0712 345 678', type: TextInputType.phone, icon: Icons.call_outlined),
              _field('whatsapp', 'WhatsApp (kama ni tofauti na simu)',
                  hint: '0712 345 678', helper: 'Maagizo yatatumwa hapa', type: TextInputType.phone, icon: Icons.chat_outlined),
              _field('email', 'Barua pepe', type: TextInputType.emailAddress, icon: Icons.mail_outline),
              _field('location', 'Mahali', hint: 'mfano: Kariakoo, Dar es Salaam', icon: Icons.place_outlined),
              _field('tin', 'TIN', helper: 'Iko kwenye ankara zake', type: TextInputType.number, icon: Icons.badge_outlined),
              _field('notes', 'Maelezo', hint: 'mfano: huleta Jumanne, hutoa mkopo wa siku 30', lines: 3, icon: Icons.notes),
              if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: Text(_busy ? 'Inahifadhi…' : 'Hifadhi'),
            ),
          ),
        ),
      ]),
    );
  }
}
