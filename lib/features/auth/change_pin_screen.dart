import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/pin_fields.dart';
import '../../core/session.dart';
import '../../core/i18n.dart';

/// Choose my own PIN.
///
/// Why it matters: every sale, void and delivery carries the name of whoever
/// signed in. That only means something if nobody else knows the PIN, not
/// even the owner. So a PIN set by the owner is temporary ([forced]: right
/// after signing in with it, no way around this screen except signing out),
/// and anyone can change theirs at any time from Zaidi.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.session, this.forced = false});

  final Session session;
  final bool forced;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _current = TextEditingController();
  final _fresh = TextEditingController();
  final _again = TextEditingController();
  final _freshFocus = FocusNode();
  final _againFocus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _fresh.dispose();
    _again.dispose();
    _freshFocus.dispose();
    _againFocus.dispose();
    super.dispose();
  }

  /// Everything checked while typing; "Hifadhi" stays off until all is fine.
  bool get _ready =>
      _current.text.length == 4 &&
      newPinStatus(_fresh.text, mustDifferFrom: _current.text) == PinStatus.good &&
      repeatStatus(_fresh.text, _again.text) == PinStatus.match;

  Future<void> _save() async {
    final current = _current.text.trim();
    final fresh = _fresh.text.trim();
    String? error;
    if (current.length != 4 || fresh.length != 4) {
      error = tr('Kila PIN iwe tarakimu 4.');
    } else if (fresh != _again.text.trim()) {
      error = tr('PIN mpya hazilingani.');
    } else if (fresh == current) {
      error = tr('PIN mpya isiwe sawa na ya sasa.');
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.changeOwnPin(current, fresh);
      if (!mounted) return;
      if (!widget.forced) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('PIN yako imebadilishwa.')));
        Navigator.of(context).pop();
      }
      // forced: the session changed and main.dart now shows the home screen.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.session.user?.name ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forced ? tr('Chagua PIN yako') : tr('Badilisha PIN yangu')),
        backgroundColor: pageBackground,
        automaticallyImplyLeading: !widget.forced, // forced: no back button
        actions: [
          if (widget.forced) TextButton(onPressed: widget.session.logout, child: const T('Toka')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: softCard(radius: 18),
            child: Text(
              widget.forced
                  ? tr('Karibu :name. PIN uliyopewa ni ya muda tu: mmiliki anaijua. Chagua PIN yako mwenyewe, ambayo ni wewe tu unaijua. Kila mauzo yatakuwa na jina lako.', {'name': name})
                  : tr('Badilisha PIN mara moja kama unadhani mtu ameiona. Usimwambie mtu yeyote PIN yako.'),
              style: const TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          PinBox(
            controller: _current,
            label: widget.forced ? tr('PIN uliyopewa') : tr('PIN ya sasa'),
            autofocus: true,
            next: _freshFocus,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 14),
          PinBox(
            controller: _fresh,
            focusNode: _freshFocus,
            next: _againFocus,
            label: tr('PIN mpya'),
            status: newPinStatus(_fresh.text, mustDifferFrom: _current.text),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 14),
          // Live: ✓ Zinalingana / ✗ Hazilingani as soon as the 4th digit is typed.
          PinBox(
            controller: _again,
            focusNode: _againFocus,
            label: tr('Rudia PIN mpya'),
            status: repeatStatus(_fresh.text, _again.text),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          const T('Usitumie 1111, 1234, mwaka wa kuzaliwa, wala PIN ya simu yako.',
              style: TextStyle(color: mutedText, fontSize: 12)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving || !_ready ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: Text(_saving ? tr('Inahifadhi…') : tr('Hifadhi PIN')),
          ),
        ],
      ),
    );
  }
}
