import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/code_boxes.dart';
import '../../core/i18n.dart';
import '../../core/phone_field.dart';
import '../../core/pin_fields.dart';
import '../../core/smooth.dart';

/// "Umesahau PIN?" (redesigned v0.48.4): three steps, each with a picture and
/// one thing to do: the phone number → the 6-digit SMS code → a new PIN.
///
/// The server (PinResetService) answers the first step the same way whether
/// the number is registered or not, allows 5 wrong codes, and signs the
/// person out of every phone and browser after the reset. This screen only
/// walks through the steps.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.api, this.phone = ''});

  final ApiClient api;
  final String phone;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

enum _Step { phone, code, pin, done }

const _bg = Color(0xFFF4F8F6);
const _ink = Color(0xFF14211D);
const _muted = Color(0xFF5B6F69);
const _green = Color(0xFF2F8A6C);

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  late final _phone = TextEditingController(text: widget.phone);
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _pin2Focus = FocusNode();
  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  String? _info;
  int _wait = 0; // seconds until "Tuma tena"
  Timer? _timer;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    for (final c in [_phone, _code, _pin, _pin2]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_phone, _code, _pin, _pin2]) {
      c.dispose();
    }
    _pin2Focus.dispose();
    super.dispose();
  }

  void _go(_Step s) {
    setState(() {
      _forward = s.index > _step.index;
      _step = s;
      _error = null;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        final res = await widget.api.post('pin/forgot', {'phone': _phone.text.trim()}) as Map<String, dynamic>;
        _info = res['message'] as String?;
        _code.clear();
        _startTimer();
        if (_step != _Step.code) _go(_Step.code);
      });

  Future<void> _check() => _run(() async {
        await widget.api.post('pin/forgot/check', {'phone': _phone.text.trim(), 'code': _code.text.trim()});
        _go(_Step.pin);
      });

  Future<void> _reset() => _run(() async {
        if (_pin.text != _pin2.text) throw ApiException(tr('PIN mbili hazifanani.'));
        await widget.api.post('pin/forgot/reset', {
          'phone': _phone.text.trim(),
          'code': _code.text.trim(),
          'pin': _pin.text,
          'pin_confirmation': _pin2.text,
        });
        HapticFeedback.lightImpact();
        _go(_Step.done);
      });

  /// "+255 712 •• •678": enough to recognise, not to copy.
  String get _masked {
    final d = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (d.length < 9) return d;
    final local = d.substring(d.length - 9);
    final cc = d.substring(0, d.length - 9);
    return '${cc.isEmpty ? '' : '+$cc '}${local.substring(0, 3)} •• •${local.substring(6)}';
  }

  bool get _ready => switch (_step) {
        _Step.phone => phoneProblem(_phone.text.trim()) == null && _phone.text.trim().isNotEmpty,
        _Step.code => _code.text.length == 6,
        _Step.pin => _pin.text.length == 4 && _pin2.text == _pin.text && !isEasyPin(_pin.text),
        _Step.done => true,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step == _Step.code) return _go(_Step.phone);
            if (_step == _Step.pin) return _go(_Step.code);
            Navigator.of(context).pop(_step == _Step.done ? _phone.text.trim() : null);
          },
        ),
        centerTitle: true,
        title: _step == _Step.done ? null : _dots(),
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              switchInCurve: Motion.curve,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: Offset(_forward ? .08 : -.08, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_step), child: _page()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots() => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _step.index ? 26 : 10,
            height: 5,
            decoration: BoxDecoration(
              color: i <= _step.index ? _green : const Color(0xFFD7E3DE),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
      ]);

  Widget _page() {
    final (icon, badge, title, text) = switch (_step) {
      _Step.phone => (Icons.lock_outline_rounded, Icons.question_mark_rounded, tr('Umesahau PIN?'),
          tr('Andika namba ya simu unayoingia nayo. Tutatuma SMS yenye namba 6.')),
      _Step.code => (Icons.sms_outlined, null, tr('Angalia SMS'), _info ?? tr('Tumetuma namba 6 kwa :p', {'p': _masked})),
      _Step.pin => (Icons.lock_reset_rounded, null, tr('Chagua PIN mpya'), tr('Tarakimu 4 utakazokumbuka. Si 1111 wala 1234.')),
      _Step.done => (Icons.lock_outline_rounded, Icons.check_rounded, tr('PIN mpya imewekwa'),
          tr('Umetolewa kwenye simu na vivinjari vyote. Ingia sasa kwa PIN mpya.')),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Center(child: StepPicture(icon: icon, badge: badge)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _muted, height: 1.4)),
        const SizedBox(height: 24),
        ...switch (_step) {
          _Step.phone => [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE3EBE7)),
                ),
                child: PhoneField(
                  controller: _phone,
                  bare: true,
                  autofocus: widget.phone.isEmpty,
                  hint: '712 345 678',
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _ready && !_busy ? _send() : null,
                ),
              ),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: tr('Laini imepotea au huna simu hiyo tena?')),
                  const TextSpan(text: ' '),
                  TextSpan(text: tr('Mwambie mmiliki wa duka, au wasiliana na Saola.'), style: const TextStyle(color: _green, fontWeight: FontWeight.w700)),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
              ),
            ],
          _Step.code => [
              CodeBoxes(
                controller: _code,
                length: 6,
                autofocus: true,
                oneTimeCode: true,
                error: _error != null,
                onChanged: (_) => setState(() => _error = null),
                onDone: (_) => _busy ? null : _check(),
              ),
              const SizedBox(height: 14),
              Center(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  child: _wait > 0
                      ? Text(tr('Tuma tena baada ya 0::s', {'s': _wait.toString().padLeft(2, '0')}),
                          key: const ValueKey('wait'), style: const TextStyle(color: _muted, fontSize: 13))
                      : TextButton.icon(
                          key: const ValueKey('again'),
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(tr('SMS haijafika? Tuma tena')),
                        ),
                ),
              ),
            ],
          _Step.pin => [
              _pinLabel(tr('PIN mpya'), newPinStatus(_pin.text)),
              CodeBoxes(
                controller: _pin,
                length: 4,
                obscure: true,
                autofocus: true,
                error: _pin.text.length == 4 && isEasyPin(_pin.text),
                onChanged: (_) => setState(() => _error = null),
                onDone: (_) => _pin2Focus.requestFocus(),
              ),
              const SizedBox(height: 18),
              _pinLabel(tr('Andika tena'), repeatStatus(_pin.text, _pin2.text)),
              CodeBoxes(
                controller: _pin2,
                focusNode: _pin2Focus,
                length: 4,
                obscure: true,
                ok: _pin2.text.length == 4 && _pin2.text == _pin.text,
                error: _pin2.text.length == 4 && _pin2.text != _pin.text,
                onChanged: (_) => setState(() => _error = null),
                onDone: (v) => v == _pin.text && !isEasyPin(v) && !_busy ? _reset() : null,
              ),
            ],
          _Step.done => const [],
        },
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(color: const Color(0xFFFBE9E5), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFC2412D), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFA8321F), fontSize: 13))),
                  ]),
                ),
        ),
        const SizedBox(height: 22),
        // Under the fields, not at the screen's bottom: the keyboard would hide it there.
        _button(),
      ],
    );
  }

  Widget _pinLabel(String label, PinStatus? s) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Row(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: _ink)),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: s == null
                ? const SizedBox.shrink()
                : Row(key: ValueKey(s.text), mainAxisSize: MainAxisSize.min, children: [
                    Icon(s.icon, size: 15, color: s.color),
                    const SizedBox(width: 4),
                    Text(tr(s.text), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.color)),
                  ]),
          ),
        ]),
      );

  Widget _button() {
    final (label, action) = switch (_step) {
      _Step.phone => (tr('Tuma namba'), _send),
      _Step.code => (tr('Endelea'), _check),
      _Step.pin => (tr('Weka PIN mpya'), _reset),
      _Step.done => (tr('Ingia sasa'), () async => Navigator.of(context).pop(_phone.text.trim())),
    };
    final on = _ready && !_busy;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      height: 50,
      child: FilledButton(
        onPressed: on ? () => action() : null,
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          disabledBackgroundColor: const Color(0xFFDDEEE6),
          disabledForegroundColor: const Color(0xFF7FA394),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(label),
      ),
    );
  }
}
