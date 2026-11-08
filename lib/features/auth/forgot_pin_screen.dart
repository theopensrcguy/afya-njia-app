import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';

/// "Umesahau PIN?": phone number → 6-digit code by SMS → new PIN.
///
/// The server (PinResetService) answers the first step the same way whether
/// the number is registered or not, allows 5 wrong codes, and signs the
/// person out of every phone and browser after the reset. This screen only
/// walks through the three steps.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.api, this.phone = ''});

  final ApiClient api;
  final String phone;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

enum _Step { phone, code, pin }

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  late final _phone = TextEditingController(text: widget.phone);
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    for (final c in [_phone, _code, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        final res = await widget.api.post('pin/forgot', {'phone': _phone.text.trim()}) as Map<String, dynamic>;
        setState(() {
          _info = res['message'] as String?;
          _step = _Step.code;
        });
      });

  Future<void> _check() => _run(() async {
        await widget.api.post('pin/forgot/check', {'phone': _phone.text.trim(), 'code': _code.text.trim()});
        setState(() {
          _info = null;
          _step = _Step.pin;
        });
      });

  Future<void> _reset() => _run(() async {
        if (_pin.text != _pin2.text) throw ApiException(tr('PIN mbili hazifanani.'));
        await widget.api.post('pin/forgot/reset', {
          'phone': _phone.text.trim(),
          'code': _code.text.trim(),
          'pin': _pin.text,
          'pin_confirmation': _pin2.text,
        });
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const T('PIN mpya imewekwa'),
            content: const T('Umetolewa kwenye simu na vivinjari vyote. Ingia sasa kwa PIN mpya.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const T('Sawa'))],
          ),
        );
        if (mounted) Navigator.pop(context, _phone.text.trim());
      });

  Widget _field(TextEditingController c, String label, {bool secret = false, int max = 4, String? hint, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        obscureText: secret,
        keyboardType: type ?? TextInputType.number,
        autofillHints: max == 6 ? const [AutofillHints.oneTimeCode] : null,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(type == TextInputType.phone ? r'[0-9+ ]' : r'[0-9]')),
          LengthLimitingTextInputFormatter(max),
        ],
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, button, action) = switch (_step) {
      _Step.phone => (
          tr('Umesahau PIN?'),
          [
            const T('Andika namba ya simu unayoingia nayo. Tutatuma SMS yenye namba ya siri ya tarakimu 6.'),
            const SizedBox(height: 16),
            _field(_phone, tr('Namba ya simu'), max: 16, hint: '0712 345 678', type: TextInputType.phone),
          ],
          tr('Tuma namba ya siri'),
          _send,
        ),
      _Step.code => (
          tr('Namba ya siri'),
          [
            if (_info != null) Text(_info!, style: const TextStyle(color: mutedText)),
            const SizedBox(height: 16),
            _field(_code, tr('Namba kutoka SMS (tarakimu 6)'), max: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _busy ? null : _send, child: const T('SMS haijafika? Tuma tena')),
            ),
          ],
          tr('Endelea'),
          _check,
        ),
      _Step.pin => (
          tr('Chagua PIN mpya'),
          [
            const T('Si 1111 wala 1234: PIN rahisi zinakataliwa.', style: TextStyle(color: mutedText)),
            const SizedBox(height: 16),
            _field(_pin, tr('PIN mpya'), secret: true),
            _field(_pin2, tr('PIN mpya tena'), secret: true),
          ],
          tr('Weka PIN mpya'),
          _reset,
        ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ...body,
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: dangerRed)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : action,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(button),
                ),
                if (_step == _Step.phone) ...[
                  const SizedBox(height: 20),
                  const T('Huna simu hiyo tena (laini imepotea)? Mwambie mmiliki wa duka, au wasiliana na Saola.',
                      style: TextStyle(color: mutedText, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
