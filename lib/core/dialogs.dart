import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

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
  String confirm = 'Weka',
  String? clearLabel,
  bool danger = false,
  bool digitsOnly = false,
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
      confirm: confirm,
      clearLabel: clearLabel,
      danger: danger,
      digitsOnly: digitsOnly,
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
  final bool required;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _showRequired = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _showRequired = true);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.digitsOnly ? TextInputType.number : TextInputType.text,
            inputFormatters: widget.digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_showRequired) setState(() => _showRequired = false);
            },
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              helperText: widget.helper,
              errorText: _showRequired ? 'Hii ni lazima' : null,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.clearLabel != null)
          TextButton(onPressed: () => Navigator.of(context).pop(''), child: Text(widget.clearLabel!))
        else
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ghairi')),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: dangerRed) : null,
          onPressed: _submit,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
