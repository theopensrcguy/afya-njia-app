import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/phone_field.dart';

/// Sajili mteja: register a customer who agreed (name, phone, their yes),
/// outside a sale. Returns true when someone was registered (or their consent
/// was recorded on an existing record with the same number).
Future<bool> registerCustomer(BuildContext context, {required ApiClient api}) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => _RegisterDialog(api: api));
  return ok == true;
}

class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog({required this.api});

  final ApiClient api;

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _agreed = false;
  bool _remind = false; // a second, optional yes
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final problem = _phone.text.isEmpty ? (_remind ? tr('Weka namba ya simu: vikumbusho vinatumwa huko.') : null) : phoneProblem(_phone.text);
    if (name.isEmpty) return setState(() => _error = tr('Weka jina la mteja.'));
    if (problem != null) return setState(() => _error = problem);
    if (!_agreed) return setState(() => _error = tr('Weka tiki: mteja amekubali.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('customers', {'name': name, 'phone': _phone.text, 'note': _note.text.trim().isEmpty ? null : _note.text.trim(), 'consent': true, 'reminders': _remind});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      final existing = e.data['customer'];
      if (e.code == 'customer_exists' && existing is Map && existing['consent'] != true && mounted) {
        // Already known (e.g. a credit customer): record their yes on that record.
        final yes = await confirmDialog(context,
            title: tr('Mteja yupo tayari'), message: '${e.message} ${tr('Weka ridhaa yake kwenye rekodi hiyo?')}', confirm: tr('Ndiyo, weka ridhaa'));
        if (yes == true) {
          try {
            await widget.api.post('customers/${asInt(existing['id'])}/consent', {'consent': true, 'reminders': _remind});
            if (mounted) Navigator.of(context).pop(true);
            return;
          } on ApiException catch (e2) {
            if (mounted) setState(() => _error = e2.message);
          }
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const T('Sajili mteja'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          T('Muulize mteja kwanza: "Tunaweza kuhifadhi dawa unazonunua hapa?" Sajili tu akisema ndiyo. Vikumbusho ni swali la pili, si lazima.',
              style: const TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: '${tr('Jina la mteja')} *')),
          const SizedBox(height: 12),
          PhoneField(controller: _phone, label: tr('Namba ya simu'), helper: tr('Kumtambua mteja. Lazima akitaka vikumbusho.')),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: InputDecoration(labelText: tr('Maelezo (si lazima)'), hintText: tr('mf. hupenda kupigiwa simu jioni'))),
          const SizedBox(height: 14),
          Material(
            color: _error != null && !_agreed ? dangerSoft : primarySoft,
            borderRadius: BorderRadius.circular(12),
            child: CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v == true),
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: T('Mteja amekubali duka lihifadhi anachonunua (historia yake). Anaweza kusema ACHA wakati wowote.',
                  style: const TextStyle(fontSize: 13, color: primaryStrong)),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
            title: const T('Pia akumbushwe dawa zikikaribia kuisha', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const T('Si lazima. SMS/WhatsApp; ujumbe hautaji jina la dawa.', style: TextStyle(fontSize: 12)),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const T('Ghairi')),
        FilledButton(onPressed: _busy ? null : _save, child: const T('Sajili')),
      ],
    );
  }
}
