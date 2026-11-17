import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';

/// "Lipia kwa simu": choose the period and the network, then the payer's phone
/// asks for their mobile money PIN; this window waits for the answer.
/// [placeId] = the owner's place in the shop being paid for (this one or another).
/// Returns true when the payment was confirmed.
Future<bool> payForShop(BuildContext context, {required ApiClient api, required int placeId, required String shopName}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PayDialog(api: api, placeId: placeId, shopName: shopName),
  );
  return ok == true;
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.api, required this.placeId, required this.shopName});

  final ApiClient api;
  final int placeId;
  final String shopName;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  final _phone = TextEditingController();
  Map<String, dynamic>? _offer;
  int? _months;
  String? _operator;
  Map<String, dynamic>? _payment; // set once the push went out
  bool _busy = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _options => ((_offer?['options'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _loadOffer() async {
    try {
      final o = await widget.api.get('billing/pay?place=${widget.placeId}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _offer = o;
        _months = _options.isEmpty ? null : (_options.first['months'] as num).toInt();
        _operator = (o['operator'] as String?) ?? 'Mpesa';
        _phone.text = '${o['phone'] ?? ''}';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.api.post('billing/pay', {
        'place': widget.placeId,
        'months': _months,
        'operator': _operator,
        'phone': _phone.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _payment = p);
      if (p['status'] == 'pending') {
        _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final id = _payment?['id'];
    if (id == null) return;
    try {
      final s = await widget.api.get('billing/pay/$id') as Map<String, dynamic>;
      if (!mounted) return;
      if (s['status'] != 'pending') _poll?.cancel();
      setState(() => _payment = s);
    } on ApiException {
      // Try again on the next tick.
    }
  }

  String _operatorLabel(String value) =>
      '${(((_offer?['operators'] as List?) ?? const []).cast<Map<String, dynamic>>().firstWhere((o) => o['value'] == value, orElse: () => {'label': value}))['label']}';

  String _monthsLabel(int m) => m == 1 ? tr('Mwezi 1') : tr('Miezi :n', {'n': m});

  String _day(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = _payment;
    if (p != null) return _waiting(p);
    final offer = _offer;
    return AlertDialog(
      title: Text(tr('Lipia :shop', {'shop': widget.shopName})),
      content: offer == null
          ? SizedBox(height: 120, child: Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader()))
          : SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const T('Utapokea ombi kwenye simu: weka PIN yako ya pesa za simu kuthibitisha. Malipo yakithibitishwa, tarehe inasogea yenyewe.',
                    style: TextStyle(color: mutedText, fontSize: 13)),
                const SizedBox(height: 12),
                const T('Muda', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in _options)
                    ChoiceChip(
                      selected: _months == (o['months'] as num).toInt(),
                      onSelected: (_) => setState(() => _months = (o['months'] as num).toInt()),
                      label: Text('${_monthsLabel((o['months'] as num).toInt())} · ${formatTsh((o['amount'] as num).toInt())}'),
                    ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _operator,
                  decoration: InputDecoration(labelText: tr('Mtandao')),
                  items: [
                    for (final o in ((offer['operators'] as List?) ?? const []).cast<Map<String, dynamic>>())
                      DropdownMenuItem(value: '${o['value']}', child: Text('${o['label']}')),
                  ],
                  onChanged: (v) => setState(() => _operator = v),
                ),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Namba itakayolipa'))),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
              ]),
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const T('Ghairi')),
        if (offer != null)
          FilledButton(onPressed: _busy || _months == null || _operator == null ? null : _pay, child: const T('Lipia sasa')),
      ],
    );
  }

  Widget _waiting(Map<String, dynamic> p) {
    final status = p['status'];
    final done = status == 'success';
    final failed = status == 'failed' || status == 'expired';
    return AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        if (done)
          const Icon(Icons.check_circle, color: brandGreen, size: 56)
        else if (failed)
          const Icon(Icons.error_outline, color: dangerRed, size: 56)
        else
          const AfyaLoader(),
        const SizedBox(height: 14),
        Text(
          done ? tr('Malipo yamepokelewa. Asante!') : failed ? tr('Malipo hayakukamilika.') : tr('Angalia simu yako'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          done
              ? tr('Duka limelipiwa mpaka :d.', {'d': _day(p['paid_until'])})
              : failed
                  ? '${p['message'] ?? ''}'
                  : tr('Weka PIN ya :op kwenye simu :phone kulipa TSh :amount.',
                      {'op': _operatorLabel('${p['operator']}'), 'phone': _phone.text.trim(), 'amount': formatTsh((p['amount'] as num).toInt()).replaceFirst('TSh ', '')}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: mutedText),
        ),
      ]),
      actions: [
        if (done)
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const T('Sawa'))
        else if (failed)
          TextButton(onPressed: () => setState(() => _payment = null), child: const T('Jaribu tena'))
        else
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const T('Funga (nitaangalia baadaye)')),
      ],
    );
  }
}
