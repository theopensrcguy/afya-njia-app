import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'cart.dart';
import '../../core/i18n.dart';

/// "How many?" with a number keypad: for quantities like 21 capsules (a 7-day
/// course), where tapping + twenty times is slow and easy to get wrong.
///
/// The number is in [unit] (kadi, boksi…). Checks stock before closing, so the
/// basket never holds more than is on the shelf. Returns the new quantity
/// (0 = remove), or null if cancelled. Used by the search and checkout screens.
Future<int?> askQuantity(BuildContext context, Product product, int current, {ProductUnit? unit}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _QuantityDialog(product: product, current: current, unit: unit ?? product.defaultUnit),
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.product, required this.current, required this.unit});

  final Product product;
  final int current;
  final ProductUnit unit;

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
    final max = Cart.maxOf(widget.product, widget.unit);
    if (value > max) {
      setState(() => _error = tr('Zinapatikana :max :a tu.', {'max': max, 'a': unitLabel(widget.unit.name, max)}));
      return;
    }
    Navigator.of(context).pop(value);
  }

  void _step(int by) {
    final v = ((int.tryParse(_controller.text.trim()) ?? 0) + by).clamp(0, 99999);
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _controller.text = '$v';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  /// v0.46.1: long product names (COFFNIL HERBAL COUGH REMEDY…) filled the
  /// dialog at title size and pushed the number out of its box. The name is
  /// now two small lines, the number sits in its own pill between − and +.
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final u = widget.unit;
    Widget round(IconData icon, VoidCallback onTap) => Material(
          color: const Color(0xFFEFF4F2),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 24))),
        );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
          const SizedBox(height: 4),
          Text(tr('Zilizopo: :a · 0 = ondoa', {'a': describeStock(p.onHand, p.units)}), style: const TextStyle(fontSize: 12, color: mutedText)),
          const SizedBox(height: 16),
          Row(children: [
            round(Icons.remove_rounded, () => _step(-1)),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _save(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixText: unitLabel(u.name, 2),
                  suffixStyle: const TextStyle(fontSize: 13, color: mutedText),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            round(Icons.add_rounded, () => _step(1)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed, fontSize: 13))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const T('Weka')),
          ]),
        ]),
      ),
    );
  }
}
