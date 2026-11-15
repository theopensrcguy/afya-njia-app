import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';

/// Did this customer agree that the shop keeps what they buy and reminds them?
bool customerAgreed(Map<String, dynamic>? c) => c != null && c['consent'] == true;

/// "2026-12-11" → "11/12/2026".
String dayText(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// "255712345678" → "0712 345 678".
String phoneText(dynamic phone) {
  final m = RegExp(r'^255(\d{3})(\d{3})(\d{3})$').firstMatch('${phone ?? ''}');
  return m == null ? '${phone ?? ''}' : '0${m[1]} ${m[2]} ${m[3]}';
}

/// "Muulize mteja": what someone buys at a pharmacy is about their health, so
/// the seller asks, and only a yes is recorded. Asks for a phone when the
/// customer has none (reminders need one). Returns the updated customer, or
/// null when they said no.
Future<Map<String, dynamic>?> askCustomerConsent(BuildContext context, {required ApiClient api, required Map<String, dynamic> customer}) {
  return showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ConsentDialog(api: api, customer: customer));
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({required this.api, required this.customer});

  final ApiClient api;
  final Map<String, dynamic> customer;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _needsPhone => '${widget.customer['phone'] ?? ''}'.isEmpty;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _yes() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await widget.api.post('customers/${widget.customer['id']}/consent', {
        'consent': true,
        if (_needsPhone && _phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
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
      title: const T('Muulize mteja'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Je, :name anakubali duka lihifadhi manunuzi yake, na kumkumbusha kwa simu dawa zake zinapokaribia kuisha?', {'name': widget.customer['name']})),
          const SizedBox(height: 8),
          const T('Anaweza kusitisha wakati wowote. Kumbukumbu zake zinaonwa na wenye ruhusa tu, na ujumbe wa kikumbusho hautaji jina la dawa.',
              style: TextStyle(color: mutedText, fontSize: 13)),
          if (_needsPhone)
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('Simu ya mteja (ya kukumbushwa)'), hintText: '07XX XXX XXX'),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const T('Hajakubali')),
        FilledButton(onPressed: _saving ? null : _yes, child: const T('Amekubali')),
      ],
    );
  }
}

/// "Mkumbushe kurudia dawa": for each medicine just sold, how many days it
/// lasts (blank = no reminder). Returns the day the customer will be
/// reminded ("2026-12-11"), or null when nothing was set.
Future<String?> askRefillReminder(
  BuildContext context, {
  required ApiClient api,
  required Map<String, dynamic> customer,
  required int saleId,
  required List<({int productId, String name})> lines,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RefillDialog(api: api, customer: customer, saleId: saleId, lines: lines),
  );
}

class _RefillDialog extends StatefulWidget {
  const _RefillDialog({required this.api, required this.customer, required this.saleId, required this.lines});

  final ApiClient api;
  final Map<String, dynamic> customer;
  final int saleId;
  final List<({int productId, String name})> lines;

  @override
  State<_RefillDialog> createState() => _RefillDialogState();
}

class _RefillDialogState extends State<_RefillDialog> {
  late final _days = [for (final _ in widget.lines) TextEditingController()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _days) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = [
      for (var i = 0; i < widget.lines.length; i++)
        if ((int.tryParse(_days[i].text.trim()) ?? 0) > 0) {'product_id': widget.lines[i].productId, 'days': int.parse(_days[i].text.trim())},
    ];
    if (items.isEmpty) {
      setState(() => _error = tr('Andika siku kwa angalau dawa moja.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await widget.api.post('customers/${widget.customer['id']}/reminders', {'sale_id': widget.saleId, 'items': items}) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop('${r['due_on'] ?? ''}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Mkumbushe :name kurudia dawa', {'name': widget.customer['name']})),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const T('Kwa dawa za kila mwezi: andika zinamtosha siku ngapi. Atakumbushwa siku chache kabla hazijaisha. Acha wazi kwa dawa asizorudia.',
              style: TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(widget.lines[i].name)),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _days[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 3,
                    decoration: InputDecoration(counterText: '', hintText: '—', suffixText: tr('siku'), isDense: true),
                  ),
                ),
              ]),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const T('Ghairi')),
        FilledButton(onPressed: _saving ? null : _save, child: const T('Weka kikumbusho')),
      ],
    );
  }
}
