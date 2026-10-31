import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../../models/staff.dart';

/// Screen 5 of the mockups: pick who you are, type a 4-digit PIN.
///
/// It is a StatefulWidget because it remembers things while you use it:
/// the staff list, who is selected, the digits typed so far, and whether
/// a login is in progress. Changing them inside setState() redraws the screen.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.session});

  final Session session;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _pinLength = 4;

  List<Staff> _staff = [];
  Staff? _selected;
  String _pin = '';
  bool _loading = true; // loading the staff list
  bool _signingIn = false; // waiting for the server to check the PIN
  String? _error;

  // Set when the PIN was right but this phone isn't approved yet.
  // The PIN is kept in memory only while waiting, so "Jaribu tena" doesn't
  // make the helper type it again. It's cleared when he leaves this view.
  String? _pairingCode;
  String _pendingPin = '';

  @override
  void initState() {
    super.initState();
    // setState() isn't allowed while the screen is still being created,
    // so start loading right after the first frame is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStaff());
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staff = await widget.session.loadStaff();
      setState(() {
        _staff = staff;
        // Preselect the helper: they sign in more often at the counter.
        _selected = staff.where((s) => !s.isOwner).firstOrNull ?? staff.firstOrNull;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tapDigit(String digit) {
    if (_signingIn || _pin.length >= _pinLength) return;
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
    final staff = _selected;
    if (staff == null) return;
    final pinToSend = pin ?? _pin;
    setState(() => _signingIn = true);
    try {
      await widget.session.login(staff, pinToSend);
      // Success: Session notifies main.dart, which swaps to HomeScreen.
      // This screen is removed, so we don't touch its state afterwards.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _signingIn = false;
        if (e.code == 'device_pending') {
          // Right PIN, new phone: switch to the "show the owner this number" view.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _staff.isEmpty
                  ? _buildLoadError()
                  : _pairingCode != null
                      ? _buildWaitingForApproval()
                      : _buildPinPad(),
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
            'Simu hii ni mpya',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mwonyeshe mmiliki namba hii ili aidhinishe simu hii.',
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
            _error ?? 'Hakuna watumiaji.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _loadStaff, child: const Text('Jaribu tena')),
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
        const Text('Nani anaingia?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),

        // Who is signing in
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final s in _staff)
              ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text('${s.name}\n${s.isOwner ? 'Mmiliki' : 'Mhudumu'}', textAlign: TextAlign.center),
                ),
                selected: _selected?.id == s.id,
                onSelected: _signingIn
                    ? null
                    : (_) => setState(() {
                          _selected = s;
                          _pin = '';
                          _error = null;
                        }),
              ),
          ],
        ),
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
