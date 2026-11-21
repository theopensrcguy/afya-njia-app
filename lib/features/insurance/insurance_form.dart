import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/smooth.dart';

/// The insurers most shops see (the server keeps the same list); any other can be typed.
const kInsurers = ['NHIF', 'Jubilee', 'Strategis', 'AAR', 'Assemble', 'Britam', 'Sanlam', 'Heritage', 'Milembe', 'Reliance', 'ZHSF'];

/// Without these three the insurer won't pay.
const kInsuranceRequired = ['insurer', 'member_number', 'patient_name'];

/// What the claim needs (v0.46.1). The three that matter come first; the rest
/// (card holder, plan, authorization, doctor, facility, prescription number,
/// diagnosis) open under "Zaidi", because insurers differ in what they ask.
/// Returns the details, or null when closed. [skipLabel] shows a "later"
/// button that returns an empty map (the till: fill it later in Madai ya bima).
Future<Map<String, String>?> askInsuranceDetails(
  BuildContext context, {
  Map<String, String> initial = const {},
  int? amount,
  String? skipLabel,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _InsuranceSheet(initial: initial, amount: amount, skipLabel: skipLabel),
  );
}

class _InsuranceSheet extends StatefulWidget {
  const _InsuranceSheet({required this.initial, this.amount, this.skipLabel});

  final Map<String, String> initial;
  final int? amount;
  final String? skipLabel;

  @override
  State<_InsuranceSheet> createState() => _InsuranceSheetState();
}

class _InsuranceSheetState extends State<_InsuranceSheet> {
  static const _fields = [
    'member_number', 'patient_name', 'patient_phone', 'principal_name', 'scheme', 'card_expiry',
    'authorization_code', 'prescriber', 'facility', 'prescription_number', 'diagnosis',
  ];
  late final _c = {for (final f in _fields) f: TextEditingController(text: widget.initial[f] ?? '')};
  late String _insurer = widget.initial['insurer'] ?? '';
  late final _other = TextEditingController(text: kInsurers.contains(_insurer) ? '' : _insurer);
  late bool _more = _fields.skip(3).any((f) => (widget.initial[f] ?? '').isNotEmpty);
  bool _tried = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _other.dispose();
    super.dispose();
  }

  String get _insurerValue => _insurer == '*' ? _other.text.trim() : _insurer;

  Map<String, String> get _values => {
        if (_insurerValue.isNotEmpty) 'insurer': _insurerValue,
        for (final e in _c.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      };

  bool get _complete => kInsuranceRequired.every((f) => (_values[f] ?? '').isNotEmpty);

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String label, {String? hint, bool required = false, String? key}) => InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          errorText: _tried && required && key != null && (_values[key] ?? '').isEmpty ? tr('Hii ni lazima kwa dai') : null,
        );
    Widget field(String key, String label, {String? hint, bool required = false, TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _c[key],
            keyboardType: type,
            textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
            onChanged: (_) => setState(() {}),
            decoration: dec(label, hint: hint, required: required, key: key),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 14 + MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .86),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.health_and_safety_outlined, color: Color(0xFF8A5300)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const T('Taarifa za bima', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(widget.amount == null ? tr('Kwa ajili ya kudai malipo') : tr('Bima inalipa TSh :a', {'a': _group(widget.amount!)}),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6F69))),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Text('${tr('Kampuni ya bima')} *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5B6F69))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in [...kInsurers, '*'])
                Pressable(
                  onTap: () {
                    tick();
                    setState(() => _insurer = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _insurer == i ? const Color(0xFF0E3B31) : const Color(0xFFEFF4F2),
                      borderRadius: BorderRadius.circular(99),
                      border: _tried && _insurerValue.isEmpty ? Border.all(color: const Color(0xFFA8321F)) : null,
                    ),
                    child: Text(i == '*' ? tr('Nyingine') : i,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _insurer == i ? Colors.white : const Color(0xFF14211D))),
                  ),
                ),
            ]),
            if (_insurer == '*') ...[
              const SizedBox(height: 10),
              TextField(controller: _other, onChanged: (_) => setState(() {}), decoration: dec(tr('Jina la kampuni'), required: true, key: 'insurer')),
            ],
            const SizedBox(height: 14),
            field('member_number', tr('Namba ya kadi ya bima'), hint: tr('kama ilivyo kwenye kadi'), required: true),
            field('patient_name', tr('Jina la mgonjwa'), required: true),
            field('patient_phone', tr('Simu ya mgonjwa (si lazima)'), type: TextInputType.phone),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _more = !_more),
                icon: Icon(_more ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: T(_more ? 'Ficha' : 'Zaidi: daktari, kibali, mpango…'),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _more
                  ? Column(children: [
                      field('principal_name', tr('Mwenye kadi (kama mgonjwa ni mtegemezi)')),
                      field('scheme', tr('Mpango / mwajiri')),
                      field('card_expiry', tr('Kadi inaisha (MM/YYYY)'), hint: '06/2027', type: TextInputType.datetime),
                      field('authorization_code', tr('Namba ya kibali (authorization)')),
                      field('prescriber', tr('Daktari aliyeandika dawa')),
                      field('facility', tr('Hospitali / kituo')),
                      field('prescription_number', tr('Namba ya cheti cha dawa')),
                      field('diagnosis', tr('Utambuzi (ICD-10 au maneno)')),
                    ])
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 6),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: const Color(0xFF0E3B31)),
              onPressed: () {
                if (!_complete) {
                  setState(() => _tried = true);
                  return;
                }
                Navigator.of(context).pop(_values);
              },
              child: const T('Hifadhi taarifa', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (widget.skipLabel != null)
              TextButton(onPressed: () => Navigator.of(context).pop(_values), child: Text(widget.skipLabel!)),
          ]),
        ),
      ),
    );
  }
}

String _group(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
