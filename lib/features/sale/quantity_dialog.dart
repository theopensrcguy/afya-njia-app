import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../../models/product.dart';

/// "How many?" with a number keypad: for quantities like 21 capsules (a 7-day
/// course), where tapping + twenty times is slow and easy to get wrong.
///
/// Checks stock before closing, so the basket never holds more than is on the
/// shelf. Returns the new quantity (0 = remove), or null if cancelled.
/// Used by both the search screen and the checkout screen.
Future<int?> askQuantity(BuildContext context, Product product, int current) {
  return showDialog<int>(
    context: context,
    builder: (context) => _QuantityDialog(product: product, current: current),
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.product, required this.current});

  final Product product;
  final int current;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the old number, so typing replaces it instead of adding to it.
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_controller.text.trim()) ?? 0;
    if (value > widget.product.onHand) {
      setState(() => _error = 'Zilizopo ni ${widget.product.onHand} tu.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      title: Text(p.name),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Idadi (${p.baseUnit})',
          helperText: 'Zilizopo: ${p.onHand} · 0 = ondoa',
          errorText: _error,
          errorStyle: const TextStyle(color: dangerRed),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ghairi')),
        FilledButton(onPressed: _save, child: const Text('Weka')),
      ],
    );
  }
}
