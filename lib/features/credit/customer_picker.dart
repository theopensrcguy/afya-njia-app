import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';

/// "Deni la nani?": pick the customer who takes (part of) the sale on credit,
/// or add a new one. A new customer added by someone who can't approve waits
/// for the owner (the server decides; the sheet just says so).
///
/// Returns the chosen customer {id, name, credit_status, available, owes}, or null.
Future<Map<String, dynamic>?> pickCustomer(BuildContext context, {required ApiClient api, required bool canApprove}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CustomerPicker(api: api, canApprove: canApprove),
  );
}

/// One line about what a customer owes and may still take.
String customerLine(Map<String, dynamic> c) {
  if (c['credit_status'] == 'blocked') return '${c['credit_status_label']}';
  final owes = (c['owes'] as num?)?.toInt() ?? 0;
  final available = (c['available'] as num?)?.toInt();
  return [
    if (owes > 0) tr('anadaiwa :a', {'a': formatTsh(owes)}),
    available == null ? tr('bila kikomo') : tr('anaweza :a zaidi', {'a': formatTsh(available)}),
  ].join(' · ');
}

/// The new-customer form; returns the created customer (or null).
Future<Map<String, dynamic>?> addCustomer(BuildContext context, {required ApiClient api, required bool canApprove, String name = ''}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _NewCustomerDialog(api: api, canApprove: canApprove, name: name),
  );
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.api, required this.canApprove});

  final ApiClient api;
  final bool canApprove;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('customers') as Map<String, dynamic>;
      if (mounted) setState(() => _all = (r['customers'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _shown {
    final q = _q.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return _all.where((c) {
      if (q.isEmpty) return c['credit_status'] != 'blocked';
      final phone = '${c['phone'] ?? ''}';
      return '${c['name']}'.toLowerCase().contains(q) || (digits.length >= 3 && phone.contains(digits.replaceFirst(RegExp(r'^0'), '')));
    }).toList();
  }

  Future<void> _new() async {
    final c = await addCustomer(context, api: widget.api, canApprove: widget.canApprove, name: _q.text.trim());
    if (c != null && mounted) Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Expanded(child: T('Deni la nani?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              TextButton.icon(onPressed: _new, icon: const Icon(Icons.person_add_alt_1_outlined), label: const T('Mteja mpya')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tafuta mteja: jina au simu…')),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: dangerRed)))
                    : ListView(children: [
                        for (final c in list)
                          ListTile(
                            title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(customerLine(c),
                                style: TextStyle(color: c['credit_status'] == 'blocked' ? dangerRed : mutedText)),
                            onTap: () => Navigator.of(context).pop(c),
                          ),
                        ListTile(
                          leading: const Icon(Icons.person_add_alt_1_outlined, color: brandGreen),
                          title: Text(_q.text.trim().isEmpty ? tr('Mteja mpya') : '${tr('Mteja mpya')}: ${_q.text.trim()}',
                              style: const TextStyle(color: brandGreen, fontWeight: FontWeight.w700)),
                          onTap: _new,
                        ),
                      ]),
          ),
        ]),
      ),
    );
  }
}

class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog({required this.api, required this.canApprove, required this.name});

  final ApiClient api;
  final bool canApprove;
  final String name;

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  late final _name = TextEditingController(text: widget.name);
  final _phone = TextEditingController();
  final _limit = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr('Weka jina la mteja.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await widget.api.post('customers', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        if (widget.canApprove && _limit.text.trim().isNotEmpty) 'credit_limit': int.tryParse(_limit.text.replaceAll(RegExp(r'\D'), '')),
      }) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const T('Mteja mpya'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.canApprove)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: T('Kila deni lako litasubiri idhini ya mmiliki.', style: TextStyle(color: mutedText)),
            ),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Jina'))),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Simu (si lazima)'), hintText: '07XX XXX XXX')),
          if (widget.canApprove)
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Kikomo cha deni (TSh, si lazima)'), hintText: tr('hakuna kikomo')),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi')),
        FilledButton(onPressed: _saving ? null : _save, child: const T('Hifadhi')),
      ],
    );
  }
}
