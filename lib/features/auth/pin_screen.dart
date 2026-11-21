import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
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
    _phoneFocus.addListener(() {
      if (mounted) setState(() {});
    });
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
    _closeKeyboard();
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
    _closeKeyboard();
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

  /// Unfocus alone isn't always enough on iOS: when the focused number box is
  /// removed in the same frame (step 1 → 2), the keyboard can stay up with
  /// nothing attached and ride along onto the home screen. So also tell the
  /// system to hide it.
  void _closeKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// True on the iPad/computer layout, where the form sits in a centred column
  /// with no height to stretch into.
  bool _wide = false;

  /// Pushes the main button to the bottom on a phone; a plain gap on the iPad.
  Widget _gap() => _wide ? const SizedBox(height: 8) : const Spacer();

  /// Key height follows the screen, so the whole screen fits without scrolling
  /// on today's iPhones (scrolling stays only as a fallback on very small ones).
  double _keyH = 60;

  // The look (agreed on the design canvas, Nov 2026): a deep green top with the
  // logo and the question, a white sheet with the one thing to do.
  static const _deep = Color(0xFF0E3B31);
  static const _mint = Color(0xFF3DDC97);
  static const _soft = Color(0xFFB7D3C9);
  static const _line = Color(0xFFDCE5E1);
  static const _keyPress = Color(0xFFE3EEE9);
  static const _sheetBg = Color(0xFFF4F8F6);

  @override
  Widget build(BuildContext context) {
    final wide = _wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      // White, not green: the iPhone keyboard has rounded top corners, and a
      // green background showed through them as two dark notches.
      backgroundColor: _sheetBg,
      // v0.47.3: the screen no longer shrinks above the keyboard; the white
      // sheet runs under it instead (its padding grows by the keyboard's
      // height). A shrinking screen left the green header showing in the
      // keyboard's rounded corners and a gap between the sheet and the keys.
      resizeToAvoidBottomInset: false,
      body: Focus(
        // On a laptop or an iPad with a keyboard, the keys type the PIN too
        // (digits, Backspace), except while the phone number is typed.
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
        child: wide
            ? _wideLayout()
            : switch (_look) {
                'glass' => _glassLayout(),
                'calm' => _calmLayout(),
                _ => _phoneLayout(),
              },
      ),
    );
  }

  /// v0.48.2, "the mix" (three directions drawn, all three used, each where it fits):
  ///   glass: "Karibu tena, Hamisi" on his own phone: deep green, calm, the PIN only.
  ///   calm:  the shared counter phone: names and PIN on white, all in thumb reach.
  ///   sheet: a new phone, or by number: a shelf header and a white sheet (number, then PIN).
  /// Type is smaller than before (titles 19–22, keys 24): it read as shouting.
  String get _look {
    if (_loading || _info == null || _pairingCode != null || _byPhone) return 'sheet';
    if (_info!.mode == 'personal' && _selected != null) return 'glass';
    if (_info!.mode == 'shared' && _info!.staff.isNotEmpty) return 'calm';
    return 'sheet';
  }

  double _keysFor(double h) => h >= 900 ? 56 : (h >= 780 ? 50 : 44);

  // ---------- A · glass (own phone) ----------

  Widget _glassLayout() {
    return ColoredBox(
      color: _deep,
      child: LayoutBuilder(builder: (context, box) {
        _keyH = _keysFor(box.maxHeight);
        return Stack(children: [
          // Two soft lights behind the glass. Painted, not blurred: cheap on old phones.
          Positioned(top: -90, right: -80, child: _glow(260, const Color(0xFF2E7D62), .55)),
          Positioned(top: box.maxHeight * .32, left: -110, child: _glow(240, const Color(0xFF1B5A47), .7)),
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - MediaQuery.paddingOf(context).vertical),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [_logo(size: 32, nameSize: 16), const Spacer(), LanguageSwitch(onDark: true, compact: true, onChanged: lang.chooseSignedOut)]),
                      const Spacer(),
                      Text(tr('Karibu tena, :a', {'a': _selected!.name.split(' ').first}),
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                      const SizedBox(height: 4),
                      const T('Weka PIN yako kuingia dukani.', style: TextStyle(color: _soft, fontSize: 13.5)),
                      const SizedBox(height: 20),
                      _pinBoxes(dark: true),
                      const SizedBox(height: 10),
                      if (_error != null) _errorLine(dark: true),
                      const SizedBox(height: 10),
                      _keypad(dark: true),
                      const SizedBox(height: 12),
                      _primary(label: _signingIn ? 'Inaingia…' : 'Ingia', onPressed: _signingIn || _pin.length < _pinLength ? null : _submit, busy: _signingIn, light: true),
                      const SizedBox(height: 8),
                      _notMeButton(dark: true),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _glow(double size, Color c, double a) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c.withValues(alpha: a), c.withValues(alpha: 0)]),
        ),
      );

  // ---------- C · calm white (shared counter phone) ----------

  Widget _calmLayout() {
    const bg = Color(0xFFF6F9F8);
    return ColoredBox(
      color: bg,
      child: LayoutBuilder(builder: (context, box) {
        _keyH = _keysFor(box.maxHeight) - 4;
        return SafeArea(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - MediaQuery.paddingOf(context).vertical),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.add_rounded, color: _mint, size: 22),
                      ),
                      const SizedBox(width: 8),
                      const Text('Afya Njia', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: inkColor)),
                      const Spacer(),
                      LanguageSwitch(compact: true, onChanged: lang.chooseSignedOut),
                    ]),
                    const SizedBox(height: 22),
                    const T('Nani anaingia?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: inkColor, letterSpacing: -0.2)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(children: [
                        for (final st in _info!.staff) ...[_calmPerson(st), const SizedBox(width: 8)],
                        // Not on the list: by number, right where they're looking.
                        GestureDetector(
                          onTap: _signingIn ? null : _usePhone,
                          child: Container(
                            width: 74,
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFB7C6C0))),
                            child: const Column(children: [
                              SizedBox(width: 38, height: 38, child: Icon(Icons.dialpad_rounded, color: mutedText)),
                              SizedBox(height: 6),
                              T('Sipo hapa', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mutedText, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _notMeButton(text: 'Sipo kwenye orodha? Ingia hapa kwa namba'),
                    const Spacer(),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (_selected != null)
                          Text(tr('PIN ya :name', {'name': _selected!.name.split(' ').first}),
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: mutedText)),
                        const SizedBox(height: 10),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _pinBoxes()),
                        if (_error != null) ...[const SizedBox(height: 10), _errorLine()],
                        const SizedBox(height: 12),
                        _keypad(),
                        const SizedBox(height: 4),
                        _primary(label: _signingIn ? 'Inaingia…' : 'Ingia', onPressed: _signingIn || _pin.length < _pinLength ? null : _submit, busy: _signingIn),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _calmPerson(Staff st) {
    final on = _selected?.id == st.id;
    final palette = [(const Color(0xFFDDF3EA), const Color(0xFF156B55)), (const Color(0xFFFDF1DC), const Color(0xFF8A5300)), (const Color(0xFFEEEDFE), const Color(0xFF3C3489)), (const Color(0xFFE6F1FB), const Color(0xFF185FA5))];
    final (bg, fg) = palette[st.id % palette.length];
    final parts = st.name.trim().split(RegExp(r'\s+'));
    final initials = ((parts.first.isEmpty ? '?' : parts.first[0]) + (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '')).toUpperCase();
    return Semantics(
      button: true,
      selected: on,
      label: st.name,
      child: GestureDetector(
        onTap: _signingIn
            ? null
            : () => setState(() {
                  _selected = st;
                  _pin = '';
                  _error = null;
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 74,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? brandGreen : Colors.transparent, width: 1.8),
          ),
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Text(initials, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Text(st.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: inkColor)),
          ]),
        ),
      ),
    );
  }

  Widget _errorLine({bool dark = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: dark ? const Color(0x33F9B4A6) : dangerSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: dark ? const Color(0xFFF9B4A6) : dangerRed, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(color: dark ? const Color(0xFFFCD9D0) : dangerRed, fontWeight: FontWeight.w600, fontSize: 13.5))),
        ]),
      );

  /// Phone: green top, white sheet. Scrolls rather than squeezing (small phones,
  /// keyboard open), and the sheet always reaches the bottom of the screen.
  Widget _phoneLayout() {
    // Green behind the top half, white behind the bottom: the header sits on
    // green, the keyboard's corners (and a bounce at the bottom) show white.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_deep, _deep, _sheetBg, _sheetBg],
          stops: [0, .5, .5, 1],
        ),
      ),
      child: LayoutBuilder(
      builder: (context, box) {
        _keyH = _keysFor(box.maxHeight);
        return GestureDetector(
          // Tap outside the number box: the keyboard goes away (iOS's number pad
          // has no Done key). Buttons still get their taps first.
          behavior: HitTestBehavior.translucent,
          onTap: _closeKeyboard,
          child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // B: a shelf of boxes behind the header (painted, so no image to download).
              Stack(children: [
                const Positioned.fill(child: _ShelfPattern()),
                SafeArea(
                  bottom: false,
                  child: Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 20), child: _header()),
                ),
              ]),
              Expanded(
                child: Container(
                  // v0.48.3: a soft mint-white, not pure white; a shadow of green above it
                  // so the header melts into the sheet instead of stopping at an edge.
                  decoration: BoxDecoration(
                    color: _sheetBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [BoxShadow(color: const Color(0xFF0B2E26).withValues(alpha: .35), blurRadius: 30, offset: const Offset(0, -8))],
                  ),
                  padding: EdgeInsets.fromLTRB(24, 22, 24,
                      16 + (MediaQuery.viewInsetsOf(context).bottom > 0 ? MediaQuery.viewInsetsOf(context).bottom : MediaQuery.paddingOf(context).bottom)),
                  child: _sheet(),
                ),
              ),
            ]),
          ),
        ),
      ),
      );
      },
    ),
    );
  }

  /// iPad / computer: the brand on the left, the form centred on the right.
  Widget _wideLayout() {
    return Row(children: [
      Container(
        width: 440,
        color: _deep,
        padding: const EdgeInsets.fromLTRB(48, 48, 48, 40),
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _logo(size: 40, withName: true, nameSize: 22),
            const Spacer(),
            T('Karibu tena', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.5)),
            const SizedBox(height: 14),
            T('Mauzo, hisa na madeni ya duka lako, mahali pamoja.', style: const TextStyle(color: _soft, fontSize: 17, height: 1.5)),
            const SizedBox(height: 24),
            _point(Icons.shopping_cart_outlined, 'Uza haraka, hata bila mtandao'),
            _point(Icons.shelves, 'Jua kilichopo rafuni, na kitakachoisha'),
            _point(Icons.verified_user_outlined, 'Kila mauzo kwa jina la aliyeingia'),
            const Spacer(),
            const Text('Saola Company Limited', style: TextStyle(color: Color(0xFF8FB5A8), fontSize: 13)),
          ]),
        ),
      ),
      Expanded(
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(padding: const EdgeInsets.fromLTRB(0, 24, 40, 0), child: LanguageSwitch(onChanged: lang.chooseSignedOut)),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: SizedBox(
                    width: 380,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      // The title the phone shows on green, here on white.
                      DefaultTextStyle.merge(style: const TextStyle(color: inkColor), child: _wideTitle()),
                      const SizedBox(height: 18),
                      _sheet(),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: _mint.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: _mint),
          ),
          const SizedBox(width: 12),
          Expanded(child: T(text, style: const TextStyle(color: Color(0xFFE4F1EC), fontSize: 15))),
        ]),
      );

  Widget _logo({double size = 36, bool withName = true, double nameSize = 19, String? sub}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(size * .28)),
        child: Icon(Icons.add_rounded, color: _deep, size: size * .8),
      ),
      if (withName) ...[
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Afya Njia', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: nameSize, letterSpacing: -0.2)),
          if (sub != null) Text(sub, style: const TextStyle(color: _soft, fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ---------- The green top (phone) ----------

  Widget _header() {
    final back = _byPhone && _phoneDone && _pairingCode == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (back)
          _roundIcon(Icons.arrow_back_rounded, tr('Rudi kwenye namba ya simu'), _editPhone)
        else
          _logo(size: 36, nameSize: 19),
        const Spacer(),
        LanguageSwitch(onDark: true, compact: true, onChanged: lang.chooseSignedOut),
      ]),
      const SizedBox(height: 16),
      ..._headerTitle(),
    ]);
  }

  Widget _roundIcon(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 20))),
        ),
      );

  List<Widget> _headerTitle() {
    // v0.47.3: 26/14 instead of 30/15, the title was out of proportion with the sheet.
    // v0.48.2: 20/13 (was 26/14): calmer next to the sheet.
    const title = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.2);
    const sub = TextStyle(color: _soft, fontSize: 13, height: 1.4);
    if (_loading || _info == null) return [T('Karibu', style: title)];
    if (_pairingCode != null) return [T('Kifaa hiki ni kipya', style: title)];
    if (_byPhone && !_phoneDone) {
      return [
        T('Karibu Afya Njia', style: title),
        // With the keyboard up, the line under the title goes, so the field and Endelea stay in view.
        if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[const SizedBox(height: 6), T('Ingia kwa namba yako ya simu na PIN.', style: sub)],
      ];
    }
    if (_byPhone) return [T('Weka PIN yako', style: title), const SizedBox(height: 10), _phoneChip(onDark: true)];
    if (_info!.mode == 'personal' && _selected != null) {
      return [
        Text(tr('Karibu tena, :a', {'a': _selected!.name.split(' ').first}), style: title),
        const SizedBox(height: 6),
        T('Weka PIN yako kuendelea.', style: sub),
        const SizedBox(height: 12),
        _notListed(onDark: true, personal: true),
      ];
    }
    // Shared counter phone: the people who use it, as cards, and right under them
    // the way in for someone who isn't there (where they're already looking).
    return [
      T('Nani anaingia?', style: title),
      const SizedBox(height: 12),
      _peopleRow(),
      const SizedBox(height: 12),
      _notListed(onDark: true, personal: false),
    ];
  }

  /// The same titles on the white side of the iPad layout.
  Widget _wideTitle() {
    const title = TextStyle(color: inkColor, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4);
    if (_loading || _info == null || _pairingCode != null) return const SizedBox.shrink();
    if (_byPhone && !_phoneDone) return T('Ingia kwa namba ya simu', style: title);
    if (_byPhone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [T('Weka PIN yako', style: title), const SizedBox(height: 10), _phoneChip(onDark: false)]);
    }
    if (_info!.mode == 'personal' && _selected != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Karibu tena, :a', {'a': _selected!.name.split(' ').first}), style: title),
        const SizedBox(height: 10),
        _notListed(onDark: false, personal: true),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      T('Nani anaingia?', style: title),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(18)),
        child: _peopleRow(),
      ),
      const SizedBox(height: 10),
      _notListed(onDark: false, personal: false),
    ]);
  }

  /// v0.48.3: "Si wewe? Ingia hapa kwa namba" as a real button (icon, words, arrow):
  /// it must look like it takes you somewhere, not like a caption.
  Widget _notMeButton({bool dark = false, String text = 'Si wewe? Ingia hapa kwa namba'}) {
    final fg = dark ? Colors.white : inkColor;
    return Material(
      color: dark ? Colors.white.withValues(alpha: .10) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? Colors.white.withValues(alpha: .22) : const Color(0xFFDCE7E2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _signingIn ? null : _usePhone,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: dark ? Colors.white.withValues(alpha: .12) : primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.smartphone_rounded, size: 18, color: dark ? _mint : brandGreen),
            ),
            const SizedBox(width: 10),
            Expanded(child: T(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14))),
            Icon(Icons.arrow_forward_rounded, size: 18, color: dark ? _mint : brandGreen),
          ]),
        ),
      ),
    );
  }

  /// "Siko kwenye orodha? Ingia kwa namba": always in view, next to the names.
  Widget _notListed({required bool onDark, required bool personal}) {
    final fg = onDark ? const Color(0xFF8FD9B8) : brandGreen;
    return Material(
      color: onDark ? Colors.white.withValues(alpha: .08) : const Color(0xFFF2F6F4),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: _signingIn ? null : _usePhone,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.smartphone_rounded, size: 17, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: T(personal ? 'Si wewe? Ingia hapa kwa namba' : 'Siko kwenye orodha? Ingia hapa kwa namba',
                  style: TextStyle(color: onDark ? Colors.white : inkColor, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }

  void _editPhone() {
    setState(() {
      _phoneDone = false;
      _pin = '';
      _error = null;
    });
    _phoneFocus.requestFocus();
  }

  /// "+255 745 941 103 · Badili": the number in use, one tap to change it.
  Widget _phoneChip({required bool onDark}) {
    final (c, local) = parsePhone(_phone.text);
    final grouped = local.replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]} ');
    return Material(
      color: onDark ? Colors.white.withValues(alpha: .10) : const Color(0xFFF2F6F4),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: _editPhone,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.flag, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text('+${c.code} $grouped', style: TextStyle(color: onDark ? Colors.white : inkColor, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 10),
            T('Badili', style: TextStyle(color: onDark ? const Color(0xFF8FD9B8) : brandGreen, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  /// Shared phone: one card per person (initials, name, role); scrolls when there are many.
  Widget _peopleRow() {
    // A scrolling Row, not a ListView: the phone layout measures this header's
    // height (IntrinsicHeight), and a ListView cannot report one.
    final staff = _info!.staff;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < staff.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          _personCard(staff[i]),
        ],
      ]),
    );
  }

  Widget _personCard(Staff s) {
    final on = _selected?.id == s.id;
    return Semantics(
      button: true,
      selected: on,
      label: s.name,
      child: GestureDetector(
        onTap: _signingIn
            ? null
            : () => setState(() {
                  _selected = s;
                  _pin = '';
                  _error = null;
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 82,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          decoration: BoxDecoration(
            color: on ? _mint.withValues(alpha: .16) : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? _mint : Colors.transparent, width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _avatar(s, size: 42, selected: on),
            const SizedBox(height: 6),
            Text(s.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(s.role == 'owner' ? tr('Mmiliki') : tr('Msaidizi'), style: const TextStyle(color: _soft, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  // ---------- The white sheet: the one thing to do ----------

  Widget _sheet() {
    if (_loading) return const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: brandGreen)));
    if (_info == null) return _buildLoadError();
    if (_pairingCode != null) return _buildWaitingForApproval();
    if (_onPhoneStep) return _phoneStep();
    return _pinStep();
  }

  Widget _steps(int at) {
    Widget dot(int n, String label) {
      final on = n <= at;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? brandGreen : const Color(0xFFEEF3F1)),
          child: Text('$n', style: TextStyle(color: on ? Colors.white : mutedText, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        T(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? brandGreen : mutedText)),
      ]);
    }

    return Row(children: [
      dot(1, 'Namba ya simu'),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 2, decoration: BoxDecoration(color: at > 1 ? brandGreen : const Color(0xFFE3EAE7), borderRadius: BorderRadius.circular(2)))),
      const SizedBox(width: 10),
      dot(2, 'PIN'),
    ]);
  }

  Widget _phoneStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _steps(1),
      const SizedBox(height: 22),
      T('Namba ya simu', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mutedText)),
      const SizedBox(height: 6),
      // v0.48.3: frosted glass: white into mint, a light edge and a soft shadow;
      // the edge turns mint while typing, a check when the number is whole.
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF2F8F5)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _error != null ? dangerRed : (_phoneReady || _phoneFocus.hasFocus ? const Color(0xFF8FD0B4) : const Color(0xFFDCE7E2)),
              width: _phoneFocus.hasFocus || _phoneReady ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: (_phoneReady || _phoneFocus.hasFocus ? brandGreen : const Color(0xFF0E3B31)).withValues(alpha: _phoneReady || _phoneFocus.hasFocus ? .13 : .06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(alignment: Alignment.centerRight, children: [
          PhoneField(
          controller: _phone,
          focusNode: _phoneFocus,
          bare: true,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: inkColor, letterSpacing: .4),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _confirmPhone(),
        ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: AnimatedScale(
              scale: _phoneReady ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check_circle_rounded, color: brandGreen, size: 22),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      _error != null
          ? Text(_error!, style: const TextStyle(color: dangerRed, fontSize: 13, fontWeight: FontWeight.w600))
          : T('Bila 0 mwanzoni. Mfano: 712 345 678', style: const TextStyle(color: Color(0xFF7B8E88), fontSize: 12)),
      const SizedBox(height: 28),
      _gap(),
      // The iPhone's number keyboard has no "Done" key: this button is the way on.
      _primary(label: 'Endelea', onPressed: _phoneReady ? _confirmPhone : null, icon: Icons.arrow_forward_rounded),
      const SizedBox(height: 6),
      Center(child: _forgotLink()),
      if ((_info!.mode != 'new' && _info!.staff.isNotEmpty) || _info!.mode == 'personal')
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _byPhone = false;
              _phoneDone = false;
              _pin = '';
              _error = null;
            }),
            child: const T('Rudi', style: TextStyle(color: mutedText, fontWeight: FontWeight.w600)),
          ),
        ),
      if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
        const SizedBox(height: 4),
        T('Kila mauzo yanahifadhiwa kwa jina la aliyeingia.', textAlign: TextAlign.center, style: const TextStyle(color: mutedText, fontSize: 12)),
      ],
    ]);
  }

  Widget _pinStep() {
    final shared = !_byPhone && _info!.mode == 'shared';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_byPhone) ...[_steps(2), const SizedBox(height: 20)],
      if (shared && _selected != null) ...[
        Text(tr('PIN ya :name', {'name': _selected!.name.split(' ').first}), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: inkColor)),
        const SizedBox(height: 12),
      ],
      _pinBoxes(),
      const SizedBox(height: 14),
      _error != null
          ? _errorLine()
          : (_byPhone
              ? T('PIN ya tarakimu 4. Ikikamilika, unaingia moja kwa moja.', textAlign: TextAlign.center, style: const TextStyle(color: mutedText, fontSize: 13.5))
              : const SizedBox.shrink()),
      const SizedBox(height: 10),
      _keypad(),
      const SizedBox(height: 12),
      _gap(),
      _primary(label: _signingIn ? 'Inaingia…' : 'Ingia', onPressed: _signingIn || _pin.length < _pinLength ? null : _submit, busy: _signingIn),
    ]);
  }

  /// [light]: the white pill on the green glass screen.
  Widget _primary({required String label, required VoidCallback? onPressed, IconData? icon, bool busy = false, bool light = false}) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          // v0.48.3: a pill, a softer green, pale mint while it can't be pressed yet.
          backgroundColor: light ? Colors.white : const Color(0xFF2F8A6C),
          foregroundColor: light ? _deep : Colors.white,
          disabledBackgroundColor: light ? Colors.white.withValues(alpha: .14) : const Color(0xFFDDEEE6),
          disabledForegroundColor: light ? _soft : const Color(0xFF7FA394),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        child: busy
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: light ? _deep : Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                T(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
              ]),
      ),
    );
  }

  /// Four boxes: filled ones show a dot, the next one is outlined in green (red after a wrong PIN).
  Widget _pinBoxes({bool dark = false}) {
    final err = _error != null && _pin.isEmpty;
    return Semantics(
      label: tr('Tarakimu :pin kati ya :pin_length', {'pin': _pin.length, 'pin_length': _pinLength}),
      child: Row(children: [
        for (var i = 0; i < _pinLength; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: _keyH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: i < _pin.length ? .16 : .08) : (i < _pin.length ? const Color(0xFFF2F8F5) : const Color(0xFFF6F9F8)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: err ? (dark ? const Color(0xFFF9B4A6) : dangerRed) : (i == _pin.length ? (dark ? _mint : brandGreen) : (dark ? Colors.transparent : _line)),
                    width: 1.6),
              ),
              child: AnimatedScale(
                scale: i < _pin.length ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: Container(width: 12, height: 12, decoration: BoxDecoration(color: dark ? Colors.white : _deep, shape: BoxShape.circle)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// Flat keys (no bubbles): the numbers carry the screen, not the buttons.
  Widget _keypad({bool dark = false}) {
    final ink = dark ? Colors.white : inkColor;
    Widget cell(Widget child) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: SizedBox(height: _keyH, child: child)));
    Widget digit(String d) => cell(Material(
          color: dark ? Colors.white.withValues(alpha: .07) : const Color(0xFFF5F8F7),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            highlightColor: dark ? Colors.white12 : _keyPress,
            onTap: () => _tapDigit(d),
            child: Center(child: Text(d, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w500, color: ink))),
          ),
        ));
    Widget row(List<Widget> c) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: c));
    return Column(children: [
      row([digit('1'), digit('2'), digit('3')]),
      row([digit('4'), digit('5'), digit('6')]),
      row([digit('7'), digit('8'), digit('9')]),
      row([
        cell(Center(child: _forgotLink(small: true, dark: dark))),
        digit('0'),
        cell(Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _backspace,
            child: Center(child: Icon(Icons.backspace_outlined, color: ink, size: 22, semanticLabel: tr('Futa'))),
          ),
        )),
      ]),
    ]);
  }

  /// "This phone is new. Show the owner this number." The owner sees the same
  /// number in his app and approves; matching numbers prove it's the right phone,
  /// even if he approves over a phone call while travelling.
  Widget _buildWaitingForApproval() {
    final code = _pairingCode!;
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      T('Mwonyeshe mmiliki namba hii ili aidhinishe kifaa hiki (simu au kompyuta).', style: const TextStyle(color: mutedText, fontSize: 15, height: 1.45)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(color: const Color(0xFFF2F8F5), borderRadius: BorderRadius.circular(18), border: Border.all(color: _line, width: 1.5)),
        child: Center(child: SelectableText(spaced, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 4, color: inkColor))),
      ),
      const SizedBox(height: 12),
      if (_error != null) Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w600)),
      const SizedBox(height: 20),
      _gap(),
      _primary(label: 'Ameidhinisha · Jaribu tena', onPressed: _signingIn ? null : () => _submit(_pendingPin), busy: _signingIn),
      const SizedBox(height: 6),
      Center(child: TextButton(onPressed: _signingIn ? null : _cancelWaiting, child: const T('Rudi', style: TextStyle(color: mutedText, fontWeight: FontWeight.w600)))),
    ]);
  }

  Widget _buildLoadError() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.wifi_off_rounded, color: mutedText, size: 40),
      const SizedBox(height: 12),
      Text(_error ?? tr('Imeshindwa kufungua.'), textAlign: TextAlign.center, style: const TextStyle(color: inkColor, fontSize: 16)),
      const SizedBox(height: 8),
      // Which server this build talks to: the first thing to check when it can't connect.
      SelectableText(apiBaseUrl, textAlign: TextAlign.center, style: const TextStyle(color: mutedText, fontSize: 12)),
      const SizedBox(height: 20),
      _primary(label: 'Jaribu tena', onPressed: _load),
    ]);
  }

  /// "Umesahau PIN?": code by SMS, new PIN. Back here with the phone number filled in.
  Widget _forgotLink({bool small = false, bool dark = false}) {
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
      child: T('Umesahau PIN?', textAlign: TextAlign.center,
          style: TextStyle(color: dark ? const Color(0xFF8FD9B8) : brandGreen, fontWeight: FontWeight.w600, fontSize: small ? 12.5 : 14, height: 1.2)),
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? _mint : Colors.white.withValues(alpha: .14)),
      child: Text(initials.toUpperCase(), style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: selected ? _deep : Colors.white)),
    );
  }
}

/// The header behind a new phone's sign-in (B): rows of boxes on shelves,
/// faint, so it reads as "a pharmacy" without a photo to download.
class _ShelfPattern extends StatelessWidget {
  const _ShelfPattern();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF0E3B31), child: CustomPaint(painter: _ShelfPainter()));
}

class _ShelfPainter extends CustomPainter {
  const _ShelfPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [Color(0x223DDC97), Color(0x18E8F3EE), Color(0x1CF5C97A)];
    final plank = Paint()..color = const Color(0x14FFFFFF);
    const rowH = 54.0;
    var row = 0;
    for (var y = 14.0; y < size.height; y += rowH, row++) {
      var x = 10.0 + (row.isOdd ? 14 : 0);
      var i = row;
      while (x < size.width) {
        final w = 22.0 + (i * 7 % 3) * 8;
        final h = 26.0 + (i * 5 % 3) * 6;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y + rowH - 12 - h, w, h), const Radius.circular(4)), Paint()..color = colors[i % 3]);
        x += w + 8;
        i++;
      }
      canvas.drawRect(Rect.fromLTWH(0, y + rowH - 10, size.width, 3), plank);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
