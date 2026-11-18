import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../../models/staff.dart';
import 'forgot_pin_screen.dart';
import '../../core/i18n.dart';
import '../../core/phone_field.dart';

/// Sign in: who you are, then a 4-digit PIN.
///
/// What it shows depends on the device (the server decides, see
/// Session.loadSignIn), so a stranger's phone or browser learns nothing:
///   personal: "Karibu tena, Hamisi" and the PIN pad. "Si wewe?" for anyone else.
///   shared:   the counter phone: round initials, most recent first.
///   new:      phone number + PIN; the device then waits for the owner's approval.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.session});

  final Session session;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _pinLength = 4;

  SignInInfo? _info;
  bool _byPhone = false; // new device, or "Si wewe?"
  // By phone, in two steps: the number (system keyboard + "Endelea"), then
  // the PIN (our keypad). One step at a time, so the phone's keyboard never
  // hides the keypad, and there is always a button to press.
  bool _phoneDone = false;
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();
  Staff? _selected;
  String _pin = '';
  bool _loading = true;
  bool _signingIn = false;
  String? _error;

  // Set when the PIN was right but this device isn't approved yet.
  // The PIN is kept in memory only while waiting, so "Jaribu tena" doesn't
  // make the person type it again. It's cleared when they leave this view.
  String? _pairingCode;
  String _pendingPin = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.session.loadSignIn();
      if (!mounted) return;
      setState(() {
        _info = info;
        _byPhone = info.mode == 'new' || (info.mode == 'shared' && info.staff.isEmpty);
        _selected = info.mode == 'personal' ? info.lastUser : (info.staff.isEmpty ? null : info.staff.first);
      });
      if (_byPhone && !_phoneDone) _phoneFocus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Step 1 → 2: the number is complete. Close the phone's keyboard; the PIN pad shows.
  void _confirmPhone() {
    if (!_phoneReady) {
      setState(() => _error = _phone.text.isEmpty ? tr('Andika namba yako ya simu kwanza.') : phoneProblem(_phone.text));
      return;
    }
    _phoneFocus.unfocus();
    setState(() {
      _phoneDone = true;
      _pin = '';
      _error = null;
    });
  }

  bool get _phoneReady => _phone.text.isNotEmpty && phoneProblem(_phone.text) == null;

  void _tapDigit(String digit) {
    if (_signingIn || _pin.length >= _pinLength) return;
    if (_byPhone && (!_phoneReady || !_phoneDone)) {
      setState(() => _error = tr('Andika namba yako ya simu kwanza.'));
      return;
    }
    setState(() {
      _pin += digit;
      _error = null;
    });
    // No "OK" button: the 4th digit submits. One less tap, many times a day.
    if (_pin.length == _pinLength) _submit();
  }

  void _backspace() {
    if (_signingIn || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit([String? pin]) async {
    if (!_byPhone && _selected == null) return;
    final pinToSend = pin ?? _pin;
    setState(() => _signingIn = true);
    try {
      await widget.session.login(_byPhone ? null : _selected, pinToSend, phone: _byPhone ? _phone.text.trim() : null);
      // Success: Session notifies main.dart, which swaps to HomeScreen.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _signingIn = false;
        if (e.code == 'device_pending') {
          // Right PIN, new device: show the owner this number.
          final wasWaiting = _pairingCode != null;
          _pairingCode = e.data['pairing_code'] as String?;
          _pendingPin = pinToSend;
          _error = wasWaiting ? tr('Bado haijaidhinishwa. Mwombe mmiliki aidhinishe.') : null;
        } else {
          _pairingCode = null;
          _pendingPin = '';
          _error = e.message;
        }
      });
    }
  }

  void _cancelWaiting() {
    setState(() {
      _pairingCode = null;
      _pendingPin = '';
      _error = null;
    });
  }

  void _usePhone() {
    setState(() {
      _byPhone = true;
      _phoneDone = false;
      _pin = '';
      _error = null;
    });
    _phoneFocus.requestFocus();
  }

  bool get _onPhoneStep => _byPhone && !_phoneDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGreen,
      body: SafeArea(
        // On a laptop or an iPad with a keyboard, the keys type the PIN too
        // (digits, Backspace, Enter), except while the phone number is typed.
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || _pairingCode != null || _onPhoneStep || _phoneFocus.hasFocus) return KeyEventResult.ignored;
            final ch = event.character;
            if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
              _tapDigit(ch);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              _backspace();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          // Scrolls instead of squeezing: on a small phone, or with the keyboard
          // open, nothing is ever pushed out of reach.
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(children: [
                  // Kiswahili / English before signing in. Becomes this person's
                  // choice when they sign in (see Session._syncLanguage).
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 14, 0),
                      child: LanguageSwitch(onDark: true, onChanged: lang.chooseSignedOut),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: _loading
                            ? const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator(color: Colors.white)))
                            : _info == null
                                ? _buildLoadError()
                                : _pairingCode != null
                                    ? _buildWaitingForApproval()
                                    : _buildPinPad(),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "This phone is new. Show the owner this number." The owner sees the same
  /// number in his app and approves; matching numbers prove it's the right phone,
  /// even if he approves over a phone call while travelling.
  Widget _buildWaitingForApproval() {
    final code = _pairingCode!;
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phonelink_lock, color: Colors.white, size: 56),
          const SizedBox(height: 16),
          Text(
            tr('Kifaa hiki ni kipya'),
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Mwonyeshe mmiliki namba hii ili aidhinishe kifaa hiki (simu au kompyuta).'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: SelectableText(
              spaced,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 4, color: inkColor),
            ),
          ),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFD7D2), fontWeight: FontWeight.w600),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brandGreen),
              onPressed: _signingIn ? null : () => _submit(_pendingPin),
              child: _signingIn
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const T('Ameidhinisha · Jaribu tena', style: TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _signingIn ? null : _cancelWaiting,
            child: const T('Rudi', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error ?? tr('Imeshindwa kufungua.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _load, child: const T('Jaribu tena')),
        ],
      ),
    );
  }

  Widget _buildPinPad() {
    return Column(
      children: [
        const SizedBox(height: 12),
        const T('AFYA NJIA', style: TextStyle(color: Colors.white70, letterSpacing: 2, fontSize: 13)),
        const SizedBox(height: 8),
        ..._who(),
        if (_onPhoneStep)
          _message()
        else ...[
          const SizedBox(height: 22),
          _dots(),
          _message(),
          _keypad(),
          const SizedBox(height: 16),
          // A visible way in, too: the 4th digit signs in by itself, but a
          // button is what people look for (and what retries after an error).
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: brandGreen,
                disabledBackgroundColor: Colors.white.withValues(alpha: .25),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _signingIn || _pin.length < _pinLength ? null : _submit,
              child: _signingIn
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const T('Ingia', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        const SizedBox(height: 22),
        T('Mauzo yote yatahifadhiwa kwa jina la aliyeingia.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _dots() {
    return Semantics(
      label: tr('Tarakimu :pin kati ya :pin_length', {'pin': _pin.length, 'pin_length': _pinLength}),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _pinLength; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? Colors.white : Colors.transparent,
                border: Border.all(color: Colors.white70, width: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _message() {
    return SizedBox(
      height: 44,
      child: Center(
        child: Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD7D2), fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Fixed-size keys (not stretched to fill the screen): the same on a phone and an iPad.
  Widget _keypad() {
    Widget row(List<Widget> keys) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: keys),
        );
    return Column(children: [
      row([_key('1'), _key('2'), _key('3')]),
      row([_key('4'), _key('5'), _key('6')]),
      row([_key('7'), _key('8'), _key('9')]),
      row([
        const SizedBox(width: 88, height: 60),
        _key('0'),
        SizedBox(
          width: 88,
          height: 60,
          child: IconButton(
            tooltip: tr('Futa'),
            onPressed: _backspace,
            icon: const Icon(Icons.backspace_outlined, color: Colors.white),
          ),
        ),
      ]),
    ]);
  }

  /// The top part: depends on the device.
  List<Widget> _who() {
    final info = _info!;
    if (_byPhone) {
      final (c, local) = parsePhone(_phone.text);
      return [
        const T('Ingia', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        T(_onPhoneStep ? 'Andika namba yako ya simu' : 'Sasa PIN yako ya tarakimu 4', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        if (_onPhoneStep) ...[
          // White card on the green: country code + the number's digits only (PhoneField).
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: PhoneField(
              controller: _phone,
              focusNode: _phoneFocus,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: inkColor),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _confirmPhone(),
            ),
          ),
          const SizedBox(height: 14),
          // The iPhone's number keyboard has no "Done" key: this button is the way on.
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: brandGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _confirmPhone,
              child: const T('Endelea', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ] else
          // Step 2: the number, small, with a way back to change it.
          Material(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () {
                setState(() {
                  _phoneDone = false;
                  _pin = '';
                  _error = null;
                });
                _phoneFocus.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${c.flag}  +${c.code} ${local.replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]} ')}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(width: 10),
                  const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                ]),
              ),
            ),
          ),
        Wrap(alignment: WrapAlignment.center, children: [
          _forgotButton(),
          if (info.mode != 'new')
            TextButton(
              onPressed: () => setState(() {
                _byPhone = false;
                _phoneDone = false;
                _pin = '';
                _error = null;
              }),
              child: const T('Rudi', style: TextStyle(color: Colors.white)),
            ),
        ]),
      ];
    }
    if (info.mode == 'personal' && _selected != null) {
      return [
        _avatar(_selected!, size: 64, selected: true),
        const SizedBox(height: 12),
        Text(tr('Karibu tena, :a', {'a': _selected!.name.split(' ').first}),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton(onPressed: _usePhone, child: const T('Si wewe?', style: TextStyle(color: Colors.white70))),
          _forgotButton(),
        ]),
      ];
    }
    // The shared counter phone: who uses it, most recent first.
    return [
      const T('Nani anaingia?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (final s in info.staff)
            InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: _signingIn
                  ? null
                  : () => setState(() {
                        _selected = s;
                        _pin = '';
                        _error = null;
                      }),
              child: SizedBox(
                width: 72,
                child: Column(children: [
                  _avatar(s, size: 52, selected: _selected?.id == s.id),
                  const SizedBox(height: 6),
                  Text(s.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: _selected?.id == s.id ? FontWeight.w800 : FontWeight.w500)),
                ]),
              ),
            ),
        ],
      ),
      Wrap(alignment: WrapAlignment.center, children: [
        TextButton(onPressed: _usePhone, child: const T('Siko kwenye orodha', style: TextStyle(color: Colors.white70))),
        _forgotButton(),
      ]),
    ];
  }

  /// "Umesahau PIN?": code by SMS, new PIN. Back here with the phone number filled in.
  Widget _forgotButton() {
    return TextButton(
      onPressed: () async {
        final phone = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => ForgotPinScreen(api: widget.session.api, phone: _byPhone ? _phone.text.trim() : '')),
        );
        if (phone != null && mounted) {
          setState(() {
            _byPhone = true;
            _phone.text = phone;
            _phoneDone = phone.isNotEmpty && phoneProblem(phone) == null;
            _pin = '';
            _error = null;
          });
        }
      },
      child: const T('Umesahau PIN?', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline)),
    );
  }

  /// Round initials: quicker to spot than a list of names.
  Widget _avatar(Staff s, {required double size, required bool selected}) {
    final parts = s.name.trim().split(RegExp(r'\s+'));
    final initials = (parts.first.isEmpty ? '?' : parts.first[0]) + (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.white : Colors.white.withAlpha(40),
        border: Border.all(color: Colors.white, width: selected ? 3 : 1),
      ),
      child: Text(initials.toUpperCase(),
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: selected ? brandGreen : Colors.white)),
    );
  }

  Widget _key(String digit) {
    return SizedBox(
      width: 88,
      height: 60,
      child: Material(
        color: Colors.white.withAlpha(30),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _tapDigit(digit),
          child: Center(
            child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
