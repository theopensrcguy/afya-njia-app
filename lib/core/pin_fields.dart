import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// The same "easy PIN" rule as the server (App\Support\PinRules), checked
/// while typing so people see it before pressing save. The server still
/// decides; this is only early feedback.
bool isEasyPin(String pin) {
  if (pin.length != 4) return false;
  const sequences = ['0123', '1234', '2345', '3456', '4567', '5678', '6789', '9876', '8765', '7654', '6543', '5432', '4321', '3210'];
  return pin.split('').toSet().length == 1 || sequences.contains(pin);
}

/// One 4-digit PIN box: digits only, never more than 4, hidden, and moves to
/// [next] by itself when the 4th digit is typed.
class PinBox extends StatelessWidget {
  const PinBox({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.next,
    this.autofocus = false,
    this.status,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final FocusNode? next;
  final bool autofocus;

  /// Shown at the end of the box: ✓ / ✗ and a word (see [PinStatus]).
  final PinStatus? status;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      // Two guards: the formatter stops a 5th digit even from paste;
      // maxLength shows nothing (counterText '') but agrees.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      maxLength: 4,
      style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800),
      onChanged: (v) {
        if (v.length == 4 && next != null) next!.requestFocus();
        onChanged?.call();
      },
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        suffixIcon: s == null ? null : Icon(s.icon, color: s.color),
        helperText: s?.text,
        helperStyle: TextStyle(color: s?.color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// What the little icon beside a PIN box says.
class PinStatus {
  const PinStatus(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;

  static const match = PinStatus(Icons.check_circle, brandGreen, 'Zinalingana');
  static const mismatch = PinStatus(Icons.cancel, dangerRed, 'Hazilingani');
  static const easy = PinStatus(Icons.error, dangerRed, 'Rahisi kubahatisha: chagua nyingine');
  static const good = PinStatus(Icons.check_circle_outline, brandGreen, 'Sawa');
}

/// Status for the NEW pin: nothing until 4 digits, then easy or fine.
PinStatus? newPinStatus(String pin, {String? mustDifferFrom}) {
  if (pin.length < 4) return null;
  if (isEasyPin(pin)) return PinStatus.easy;
  if (mustDifferFrom != null && pin == mustDifferFrom) {
    return const PinStatus(Icons.error, dangerRed, 'Sawa na ya sasa: chagua tofauti');
  }
  return PinStatus.good;
}

/// Status for the REPEAT box: nothing until it has 4 digits, then ✓ or ✗.
PinStatus? repeatStatus(String pin, String again) {
  if (again.length < 4) return null;
  return pin == again ? PinStatus.match : PinStatus.mismatch;
}

/// The owner sets a temporary PIN (new staff, reset): new + repeat, stacked,
/// with live checks; "Weka" only enabled when both are fine.
/// Returns the PIN, or null if cancelled.
Future<String?> askNewPin(BuildContext context, {required String title, String? message}) {
  return showDialog<String>(context: context, builder: (_) => _NewPinDialog(title: title, message: message));
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({required this.title, this.message});

  final String title;
  final String? message;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  final _againFocus = FocusNode();

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    _againFocus.dispose();
    super.dispose();
  }

  bool get _ok => newPinStatus(_pin.text) == PinStatus.good && repeatStatus(_pin.text, _again.text) == PinStatus.match;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.message!)),
          PinBox(
            controller: _pin,
            label: 'PIN (tarakimu 4)',
            autofocus: true,
            next: _againFocus,
            status: newPinStatus(_pin.text),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          PinBox(
            controller: _again,
            focusNode: _againFocus,
            label: 'Rudia PIN',
            status: repeatStatus(_pin.text, _again.text),
            onChanged: () => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ghairi')),
        FilledButton(onPressed: _ok ? () => Navigator.of(context).pop(_pin.text) : null, child: const Text('Weka')),
      ],
    );
  }
}
