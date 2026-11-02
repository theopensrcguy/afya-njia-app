import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import 'cart.dart';
import 'quantity_dialog.dart';

/// Checkout: the basket in full, quantities, discount, payment, "Kamilisha".
///
/// Why a separate screen: on the search screen the basket competed for space
/// with the results and the keyboard. Here it has the whole screen, and the
/// search screen keeps the whole screen for searching.
///
/// It shares the SAME Cart object as the search screen (passed in, not copied),
/// so a change here shows there instantly and nothing has to be synced.
/// Pops with `true` when a sale was completed.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.api, required this.cart});

  final ApiClient api;
  final Cart cart;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _submitting = false;

  Cart get _cart => widget.cart;

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final sale = await widget.api.post('sales', _cart.toRequest()) as Map<String, dynamic>;
      if (!mounted) return;
      await _showReceipt(sale);
      _cart.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (_isUncertain(e)) {
        // We don't know if it was saved. Freeze the basket; the retry
        // button resends the SAME sale id, so it can never count twice.
        _cart.markUncertain();
        _showMessage('Mtandao umekatika. Mauzo hayajathibitishwa. Bonyeza "Tuma tena".');
      } else {
        // A clear "no" from the server: nothing was saved, the basket can be fixed.
        // The message is already the right Swahili sentence,
        // e.g. "Punguzo zaidi ya 10% linahitaji mmiliki."
        _cart.markRejected();
        _showMessage(e.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Errors where the sale MIGHT have been saved: the request may have reached
  /// the server before the network dropped, or the server failed half-way.
  /// Everything else (wrong discount, not enough stock, ...) is a definite "no".
  bool _isUncertain(ApiException e) =>
      e.code == 'offline' || e.code == 'timeout' || (e.status != null && e.status! >= 500);

  Future<void> _showReceipt(Map<String, dynamic> sale) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: brandGreen, size: 48),
        title: const Text('Mauzo yamekamilika'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sale['receipt_number'] as String, style: const TextStyle(color: mutedText)),
            const SizedBox(height: 8),
            Text(formatTsh(sale['total'] as int), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Mteja anayefuata')),
        ],
      ),
    );
  }

  Future<void> _editDiscount() async {
    final value = await askText(
      context,
      title: 'Punguzo (TSh)',
      label: 'Kiasi',
      helper: 'Jumla: ${formatTsh(_cart.subtotal)}',
      initial: _cart.discount == 0 ? '' : '${_cart.discount}',
      digitsOnly: true,
      clearLabel: 'Ondoa', // "Ondoa" returns '' = no discount
    );
    if (value != null) _cart.setDiscount(int.tryParse(value) ?? 0);
  }

  Future<void> _typeQuantity(CartLine line) async {
    final value = await askQuantity(context, line.product, line.quantity, unit: line.unit);
    if (value == null || !mounted) return;
    if (!_cart.setQuantity(line.product.id, value)) {
      _showMessage('Hisa haitoshi: ${line.product.name} (zilizopo ${describeStock(line.product.onHand, line.product.units)}).');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: dangerRed));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) => PopScope(
        // While a sale is uncertain, leaving would throw away a basket that
        // may or may not have been recorded, so the back button is blocked.
        canPop: !_cart.uncertain,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _showMessage('Tuma mauzo haya kwanza kabla ya kutoka.');
        },
        child: Scaffold(
          appBar: AppBar(title: Text('Kikapu · ${_cart.itemCount} bidhaa')),
          body: _cart.isEmpty ? _buildEmpty() : _buildBasket(),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Kikapu ni tupu.', style: TextStyle(color: mutedText)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const Text('Rudi kutafuta')),
        ],
      ),
    );
  }

  Widget _buildBasket() {
    return Column(
      children: [
        if (_cart.uncertain)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Mauzo haya hayajathibitishwa kwa sababu ya mtandao. Kikapu kimefungwa. '
              'Bonyeza "Tuma tena" hadi yathibitishwe. Hayatahesabiwa mara mbili.',
              style: TextStyle(color: warnAmber, fontWeight: FontWeight.w600),
            ),
          ),
        // The lines get all the space that's left, and scroll if there are many.
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _cart.lines.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, i) => _line(_cart.lines[i]),
          ),
        ),
        _buildPayPanel(),
      ],
    );
  }

  Widget _line(CartLine line) {
    final p = line.product;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${formatTsh(line.unit.price)} × ${line.quantity} ${unitLabel(line.unit.name, line.quantity)}',
                    style: const TextStyle(fontSize: 12, color: mutedText)),
              ],
            ),
          ),
          IconButton(
            tooltip: line.quantity == 1 ? 'Ondoa' : 'Punguza',
            onPressed: _cart.canEdit ? () => _cart.setQuantity(p.id, line.quantity - 1) : null,
            icon: Icon(line.quantity == 1 ? Icons.delete_outline : Icons.remove_circle_outline),
          ),
          // Tap the number to type an exact amount (e.g. 21 for a 7-day course).
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _cart.canEdit ? () => _typeQuantity(line) : null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFE7F1EC), borderRadius: BorderRadius.circular(8)),
              child: Text('${line.quantity}', style: const TextStyle(color: brandGreen, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          IconButton(
            tooltip: 'Ongeza',
            onPressed: _cart.canEdit
                ? () {
                    if (!_cart.setQuantity(p.id, line.quantity + 1)) {
                      _showMessage('Hisa haitoshi: ${p.name} (zilizopo ${describeStock(p.onHand, p.units)}).');
                    }
                  }
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
          SizedBox(
            width: 88,
            child: Text(formatTsh(line.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildPayPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(blurRadius: 12, color: Color(0x22000000))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _cart.canEdit ? _editDiscount : null,
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: Text(_cart.discount > 0 ? 'Punguzo ${formatTsh(_cart.discount)}' : 'Punguzo'),
                  ),
                  const Spacer(),
                  const Text('Jumla ', style: TextStyle(color: mutedText)),
                  Text(formatTsh(_cart.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Taslimu')),
                  ButtonSegment(value: 'mobile', label: Text('Simu')),
                  ButtonSegment(value: 'insurance', label: Text('Bima')),
                ],
                selected: {_cart.paymentMethod},
                onSelectionChanged: _cart.canEdit ? (s) => _cart.setPaymentMethod(s.first) : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _submitting ? null : _completeSale,
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _cart.uncertain ? 'Tuma tena · ${formatTsh(_cart.total)}' : 'Kamilisha mauzo · ${formatTsh(_cart.total)}',
                          style: const TextStyle(fontSize: 17),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
