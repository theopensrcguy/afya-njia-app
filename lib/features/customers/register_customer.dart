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
///
/// v0.47: a full sheet instead of a cramped dialog: labels above the fields,
/// the country code joined to the number, the required "yes" as a card to
/// tick and the optional reminders as a separate switch, Ghairi / Sajili at
/// the bottom.
Future<bool> registerCustomer(BuildContext context, {required ApiClient api}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF5F8F7),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _RegisterDialog(api: api),
  );
  return ok == true;
}

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _muted = Color(0xFF5B6F69);

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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 6),
        child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
      );

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFC9D6D1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _deep, width: 1.6)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final missingYes = _error != null && !_agreed;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0E5A44)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    T('Sajili mteja', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
                    T('Uliza kwanza, sajili akikubali', style: TextStyle(fontSize: 12.5, color: _muted)),
                  ]),
                ),
                IconButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.record_voice_over_outlined, size: 18, color: _muted),
                      const SizedBox(width: 8),
                      Expanded(child: T('Muulize: "Tunaweza kuhifadhi dawa unazonunua hapa?" Sajili tu akisema ndiyo.', style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.35))),
                    ]),
                  ),
                  _label('${tr('Jina la mteja')} *'),
                  TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _box(tr('mf. Asha Juma'))),
                  _label(tr('Namba ya simu')),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC9D6D1))),
                    child: PhoneField(controller: _phone, bare: true, hint: '712 345 678'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 5),
                    child: T(_remind ? 'Lazima: vikumbusho vinatumwa huko.' : 'Si lazima, ila inahitajika kwa vikumbusho.', style: const TextStyle(fontSize: 11.5, color: _muted)),
                  ),
                  _label(tr('Maelezo (si lazima)')),
                  TextField(controller: _note, decoration: _box(tr('mf. mama wa Neema, hupenda kupigiwa jioni'))),
                  _label(tr('Ridhaa')),
                  // The yes that is required, as a card to tick.
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _agreed = !_agreed),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: missingYes ? dangerRed : (_agreed ? const Color(0xFF0E5A44) : const Color(0xFFC9D6D1)), width: _agreed || missingYes ? 1.6 : 1),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(_agreed ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: missingYes ? dangerRed : const Color(0xFF0E5A44), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              T('Amekubali historia yake ihifadhiwe *', style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                              const SizedBox(height: 2),
                              T('Anaweza kusema ACHA wakati wowote.', style: const TextStyle(fontSize: 12, color: _muted)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // The second yes, optional.
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC9D6D1))),
                    child: Row(children: [
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          T('Pia akumbushwe dawa ikikaribia kuisha', style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                          SizedBox(height: 2),
                          T('SMS/WhatsApp · ujumbe hautaji jina la dawa', style: TextStyle(fontSize: 12, color: _muted)),
                        ]),
                      ),
                      Switch(value: _remind, onChanged: (v) => setState(() => _remind = v)),
                    ]),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const T('Ghairi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: _deep,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? tr('Inasajili…') : tr('Sajili mteja'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
