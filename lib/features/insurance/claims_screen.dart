import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'insurance_form.dart';

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _muted = Color(0xFF5B6F69);
const _bg = Color(0xFFF2F6F4);

/// Madai ya bima (v0.46.1): what the insurers owe the shop, per insurer, and
/// each sale's claim: fill what's missing, mark it sent, paid or rejected.
class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  String _status = 'open';
  String? _insurer;
  Map<String, dynamic>? _d;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('insurance-claims', query: {'status': _status, 'insurer': ?_insurer}) as Map<String, dynamic>;
      if (mounted) setState(() => (_d = d, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _patch(Map<String, dynamic> c, Map<String, dynamic> body, String done) async {
    try {
      await _api.patch('insurance-claims/${c['id']}', body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _edit(Map<String, dynamic> c) async {
    final initial = <String, String>{
      for (final k in ['insurer', 'member_number', 'patient_name', 'principal_name', 'scheme', 'card_expiry', 'authorization_code', 'prescriber', 'facility', 'prescription_number', 'diagnosis', 'patient_phone'])
        if (c[k] != null) k: '${c[k]}',
    };
    final d = await askInsuranceDetails(context, initial: initial, amount: asInt(c['amount']));
    if (d != null) await _patch(c, d, tr('Imehifadhiwa.'));
  }

  Future<void> _paid(Map<String, dynamic> c) async {
    final amount = TextEditingController(text: groupDigits(asInt(c['amount'])));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const T('Bima imelipa kiasi gani?'),
        content: TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: const [MoneyInput()],
            decoration: InputDecoration(labelText: tr('Kiasi (TSh)'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const T('Imelipwa')),
        ],
      ),
    );
    if (ok == true) await _patch(c, {'status': 'paid', 'paid_amount': moneyValue(amount.text) ?? asInt(c['amount'])}, tr('Imewekwa: imelipwa.'));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const T('Madai ya bima', style: TextStyle(fontWeight: FontWeight.w800))),
      body: d == null
          ? Center(child: _error != null ? Text(_error!) : const AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: staggered([
                _hero((d['summary'] as Map).cast<String, dynamic>()),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (k, label) in [
                      ('open', tr('Zinadaiwa')),
                      ('incomplete', tr('Hazijakamilika')),
                      ('pending', tr('Tayari kudai')),
                      ('submitted', tr('Zimetumwa')),
                      ('paid', tr('Zimelipwa')),
                      ('rejected', tr('Zimekataliwa')),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _status == k,
                          onSelected: (_) {
                            setState(() => _status = k);
                            _load();
                          },
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                if ((d['claims'] as List).isEmpty)
                  const Padding(padding: EdgeInsets.all(32), child: T('Hakuna madai hapa.', textAlign: TextAlign.center, style: TextStyle(color: _muted))),
                for (final c in (d['claims'] as List).cast<Map<String, dynamic>>()) _claim(c),
              ])),
            ),
    );
  }

  Widget _hero(Map<String, dynamic> s) {
    final by = ((s['by_insurer'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Bima zinadaiwa', style: TextStyle(color: Colors.white70, fontSize: 13)),
        CountUp(value: asInt(s['owed']), format: formatTsh, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          tr('Hazijakamilika :a · tayari :b · zimetumwa :c', {'a': s['incomplete'] ?? 0, 'b': s['pending'] ?? 0, 'c': s['submitted'] ?? 0}),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (asInt(s['paid_month']) > 0)
          Text(tr('Zimelipwa mwezi huu: :a', {'a': formatTsh(asInt(s['paid_month']))}), style: const TextStyle(color: Color(0xFF3DDC97), fontSize: 12, fontWeight: FontWeight.w700)),
        if (by.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in by)
              Pressable(
                onTap: () {
                  setState(() => _insurer = _insurer == b['insurer'] ? null : b['insurer'] as String?);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _insurer == b['insurer'] ? const Color(0xFF3DDC97) : Colors.white12,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('${b['insurer'] ?? tr('Haijulikani')} · ${groupDigits(asInt(b['amount']))}',
                      style: TextStyle(color: _insurer == b['insurer'] ? _deep : Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _claim(Map<String, dynamic> c) {
    final status = '${c['status']}';
    final missing = ((c['missing'] as List?) ?? const []).isNotEmpty;
    final (bg, fg) = switch (status) {
      'incomplete' => (const Color(0xFFFFF4DC), const Color(0xFF8A5300)),
      'pending' => (const Color(0xFFE7F0FF), const Color(0xFF2F5FB0)),
      'submitted' => (const Color(0xFFF0ECF7), const Color(0xFF5B4790)),
      'paid' => (const Color(0xFFE7F6EF), const Color(0xFF0E5A44)),
      _ => (const Color(0xFFFBE9E5), const Color(0xFFA8321F)),
    };
    final at = DateTime.tryParse('${c['sold_at']}')?.toLocal();
    final items = ((c['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(c['patient_name'] == null ? tr('Mgonjwa hajaandikwa') : '${c['patient_name']}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
          ),
          Text(formatTsh(asInt(c['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        ]),
        const SizedBox(height: 2),
        Text(
          [c['insurer'] ?? tr('Bima?'), if (c['member_number'] != null) '#${c['member_number']}', '${c['receipt_number']}', if (at != null) swahiliDate(at)].join(' · '),
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(items.map((i) => '${i['name']} ×${i['quantity']}').join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
            child: Text('${c['status_label']}', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const Spacer(),
          if (status != 'cancelled' && status != 'paid')
            TextButton(onPressed: () => _edit(c), child: T(missing ? 'Jaza' : 'Hariri')),
          if (status == 'pending')
            FilledButton(onPressed: () => _patch(c, {'status': 'submitted'}, tr('Imewekwa: imetumwa.')), child: const T('Imetumwa')),
          if (status == 'submitted') ...[
            TextButton(onPressed: () => _patch(c, {'status': 'rejected'}, tr('Imewekwa: imekataliwa.')), child: const T('Imekataliwa')),
            FilledButton(onPressed: () => _paid(c), child: const T('Imelipwa')),
          ],
        ]),
      ]),
    );
  }
}
