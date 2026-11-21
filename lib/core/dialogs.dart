import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'money.dart';

import 'brand.dart';
import 'i18n.dart';

/// A dialog that asks for one piece of text (a reason, an amount).
///
/// Why a StatefulWidget instead of a TextEditingController created in the
/// caller: if the caller disposes its controller as soon as showDialog
/// returns, the dialog is still animating closed and uses it for a few more
/// frames, which crashes ("used after being disposed"). Here the dialog owns
/// the controller and Flutter disposes it at exactly the right time.
///
/// Returns the trimmed text, or null if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? message,
  required String label,
  String? hint,
  String? helper,
  String initial = '',
  String? confirm,
  String? clearLabel,
  bool danger = false,
  bool digitsOnly = false,
  bool money = false,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      message: message,
      label: label,
      hint: hint,
      helper: helper,
      initial: initial,
      confirm: confirm ?? tr('Weka'),
      clearLabel: clearLabel,
      danger: danger,
      digitsOnly: digitsOnly || money,
      money: money,
      required: required,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.hint,
    required this.helper,
    required this.initial,
    required this.confirm,
    required this.clearLabel,
    required this.danger,
    required this.digitsOnly,
    this.money = false,
    required this.required,
  });

  final String title;
  final String? message;
  final String label;
  final String? hint;
  final String? helper;
  final String initial;
  final String confirm;
  final String? clearLabel;
  final bool danger;
  final bool digitsOnly;
  final bool money; // grouped as 125,000; returned without the commas
  final bool required;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(
      text: widget.money && moneyValue(widget.initial) != null ? groupDigits(moneyValue(widget.initial)!) : widget.initial);
  bool _showRequired = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    final text = widget.money ? raw.replaceAll(',', '') : raw;
    if (widget.required && text.isEmpty) {
      setState(() => _showRequired = true);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Titles can be product names: two lines at most, readable size (v0.46.1).
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25)),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.digitsOnly ? TextInputType.number : TextInputType.text,
            inputFormatters: widget.money ? const [MoneyInput()] : (widget.digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null),
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_showRequired) setState(() => _showRequired = false);
            },
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              helperText: widget.helper,
              errorText: _showRequired ? tr('Hii ni lazima') : null,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.clearLabel != null)
          TextButton(onPressed: () => Navigator.of(context).pop(''), child: Text(widget.clearLabel!))
        else
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi')),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: dangerRed) : null,
          onPressed: _submit,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Yes / no, said plainly. Returns true only on "yes".
Future<bool?> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(tr('Ghairi'))),
        FilledButton(
          onPressed: () => Navigator.of(d).pop(true),
          style: danger ? FilledButton.styleFrom(backgroundColor: dangerRed) : null,
          child: Text(confirm),
        ),
      ],
    ),
  );
}
