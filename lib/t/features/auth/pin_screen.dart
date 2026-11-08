import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../../models/staff.dart';

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
      if (_byPhone) _phoneFocus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _phoneReady => _phone.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 9;

  void _tapDigit(String digit) {
    if (_signingIn || _pin.length >= _pinLength) return;
    if (_byPhone && !_phoneReady) {
      setState(() => _error = 'Andika namba yako ya simu kwanza.');
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
          _error = wasWaiting ? 'Bado haijaidhinishwa. Mwombe mmiliki aidhinishe.' : null;
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
      _pin = '';
      _error = null;
    });
    _phoneFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGreen,
      body: SafeArea(
        // On a laptop the keyboard types the PIN too (digits, Backspace),
        // except while the phone-number field is being typed in.
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || _pairingCode != null || _phoneFocus.hasFocus) return KeyEventResult.ignored;
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
          // Phone-sized in the middle of a wide screen.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 820),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _info == null
                        ? _buildLoadError()
                        : _pairingCode != null
                            ? _buildWaitingForApproval()
                            : _buildPinPad(),
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
          const Text(
            'Kifaa hiki ni kipya',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mwonyeshe mmiliki namba hii ili aidhinishe kifaa hiki (simu au kompyuta).',
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
                  : const Text('Ameidhinisha · Jaribu tena', style: TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _signingIn ? null : _cancelWaiting,
            child: const Text('Rudi', style: TextStyle(color: Colors.white)),
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
            _error ?? 'Imeshindwa kufungua.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _load, child: const Text('Jaribu tena')),
        ],
      ),
    );
  }

  Widget _buildPinPad() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text('AFYA NJIA', style: TextStyle(color: Colors.white70, letterSpacing: 2, fontSize: 13)),
        const SizedBox(height: 8),
        ..._who(),
        const SizedBox(height: 32),

        // The four dots
        Semantics(
          label: 'Tarakimu ${_pin.length} kati ya $_pinLength',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pinLength; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
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
        ),
        SizedBox(
          height: 40,
          child: Center(
            child: _signingIn
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_error ?? '', style: const TextStyle(color: Color(0xFFFFD7D2), fontWeight: FontWeight.w600)),
          ),
        ),

        // Keypad
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _key(d),
              const SizedBox.shrink(),
              _key('0'),
              IconButton(
                tooltip: 'Futa',
                onPressed: _backspace,
                icon: const Icon(Icons.backspace_outlined, color: Colors.white),
              ),
            ],
          ),
        ),
        const Text(
          'Mauzo yote yatahifadhiwa kwa jina la aliyeingia.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  /// The top part: depends on the device.
  List<Widget> _who() {
    final info = _info!;
    if (_byPhone) {
      return [
        const Text('Ingia', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Namba yako ya simu na PIN', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        TextField(
          controller: _phone,
          focusNode: _phoneFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(16)],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: inkColor),
          onChanged: (_) => setState(() => _error = null),
          // Enter: on to the PIN (the keypad, or the keyboard's digits).
          onSubmitted: (_) => _phoneFocus.unfocus(),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: '0712 345 678',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (info.mode != 'new')
          TextButton(
            onPressed: () => setState(() {
              _byPhone = false;
              _pin = '';
              _error = null;
            }),
            child: const Text('Rudi', style: TextStyle(color: Colors.white)),
          ),
      ];
    }
    if (info.mode == 'personal' && _selected != null) {
      return [
        _avatar(_selected!, size: 64, selected: true),
        const SizedBox(height: 12),
        Text('Karibu tena, ${_selected!.name.split(' ').first}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        TextButton(onPressed: _usePhone, child: const Text('Si wewe?', style: TextStyle(color: Colors.white70))),
      ];
    }
    // The shared counter phone: who uses it, most recent first.
    return [
      const Text('Nani anaingia?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
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
      TextButton(onPressed: _usePhone, child: const Text('Siko kwenye orodha', style: TextStyle(color: Colors.white70))),
    ];
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
    return Material(
      color: Colors.white.withAlpha(30),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _tapDigit(digit),
        child: Center(
          child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
