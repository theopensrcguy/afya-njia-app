import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart' show paymentLabels;
import '../../core/money.dart';
import '../../core/units.dart';
import 'cart.dart';
import 'quantity_dialog.dart';
import '../../core/i18n.dart';

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
        _showMessage(tr('Mtandao umekatika. Mauzo hayajathibitishwa. Bonyeza "Tuma tena".'));
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

  /// The receipt as plain text: what WhatsApp sends. Built from the basket
  /// (still full while the dialog is open) and the server's sale.
  String _receiptText(Map<String, dynamic> sale) {
    final shop = (sale['shop'] as Map?) ?? const {};
    final parts = (sale['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final discount = (sale['discount'] as num?)?.toInt() ?? 0;
    return [
      '*${shop['name'] ?? ''}*',
      if ((shop['location'] ?? '').toString().isNotEmpty) '${shop['location']}',
      '${tr('Risiti')} ${sale['receipt_number']}',
      '',
      for (final l in _cart.lines)
        '${l.product.name}\n  ${l.quantity} ${unitLabel(l.unit.name, l.quantity)} × ${formatTsh(l.unit.price)} = ${formatTsh(l.lineTotal)}',
      '',
      if (discount > 0) '${tr('Punguzo')}: -${formatTsh(discount)}',
      '*${tr('Jumla')}: ${formatTsh(sale['total'] as int)}*',
      for (final p in parts) '${paymentLabels[p['method']] ?? p['method']}: ${formatTsh(p['amount'] as int)}',
      '',
      if (sale['seller'] != null) tr('Umehudumiwa na :name', {'name': sale['seller']}),
      tr('Asante!'),
    ].join('\n');
  }

  /// Opens WhatsApp with the receipt typed in; the seller picks the customer's chat.
  Future<void> _shareReceipt(Map<String, dynamic> sale, BuildContext dialogContext) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_receiptText(sale))}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(tr('WhatsApp haikufunguka kwenye simu hii.'))));
    }
  }

  Future<void> _showReceipt(Map<String, dynamic> sale) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (receipt) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: brandGreen, size: 48),
        title: const T('Mauzo yamekamilika'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sale['receipt_number'] as String, style: const TextStyle(color: mutedText)),
            const SizedBox(height: 8),
            Text(formatTsh(sale['total'] as int), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            // Paid in parts: say how, so the seller can check before the customer leaves.
            if ((sale['payments'] as List?)?.length case final n? when n > 1) ...[
              const SizedBox(height: 6),
              for (final p in (sale['payments'] as List).cast<Map<String, dynamic>>())
                Text('${paymentLabels[p['method']] ?? p['method']}: ${formatTsh(p['amount'] as int)}', style: const TextStyle(color: mutedText)),
            ],
          ],
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          OutlinedButton.icon(
            onPressed: () => _shareReceipt(sale, receipt),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const T('Tuma kwa WhatsApp'),
          ),
          FilledButton(onPressed: () => Navigator.of(receipt).pop(), child: const T('Mteja anayefuata')),
        ],
      ),
    );
  }

  Future<void> _editDiscount() async {
    final value = await askText(
      context,
      title: tr('Punguzo (TSh)'),
      label: tr('Kiasi'),
      helper: tr('Jumla: :a', {'a': formatTsh(_cart.subtotal)}),
      initial: _cart.discount == 0 ? '' : '${_cart.discount}',
      digitsOnly: true,
      clearLabel: tr('Ondoa'), // "Ondoa" returns '' = no discount
    );
    if (value != null) _cart.setDiscount(int.tryParse(value) ?? 0);
  }

  Future<void> _typeQuantity(CartLine line) async {
    final value = await askQuantity(context, line.product, line.quantity, unit: line.unit);
    if (value == null || !mounted) return;
    if (!_cart.setQuantity(line.product.id, value)) {
      _showMessage(tr('Hisa haitoshi: :name (zilizopo :a).', {'name': line.product.name, 'a': describeStock(line.product.onHand, line.product.units)}));
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
          if (!didPop) _showMessage(tr('Tuma mauzo haya kwanza kabla ya kutoka.'));
        },
        child: Scaffold(
          appBar: AppBar(title: Text(tr('Kikapu · :item_count bidhaa', {'item_count': _cart.itemCount}))),
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
          const T('Kikapu ni tupu.', style: TextStyle(color: mutedText)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const T('Rudi kutafuta')),
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
            child: Text(
              tr('Mauzo haya hayajathibitishwa kwa sababu ya mtandao. Kikapu kimefungwa. Bonyeza "Tuma tena" hadi yathibitishwe. Hayatahesabiwa mara mbili.'),
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
            tooltip: line.quantity == 1 ? tr('Ondoa') : tr('Punguza'),
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
            tooltip: tr('Ongeza'),
            onPressed: _cart.canEdit
                ? () {
                    if (!_cart.setQuantity(p.id, line.quantity + 1)) {
                      _showMessage(tr('Hisa haitoshi: :name (zilizopo :a).', {'name': p.name, 'a': describeStock(p.onHand, p.units)}));
                    }
                  }
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
          SizedBox(
            width: 80,
            child: Text(formatTsh(line.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          // × : the whole line out, whatever the quantity.
          IconButton(
            tooltip: tr('Ondoa'),
            visualDensity: VisualDensity.compact,
            onPressed: _cart.canEdit ? () => _cart.setQuantity(p.id, 0) : null,
            icon: const Icon(Icons.close, size: 20, color: mutedText),
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
        // With the keyboard up (typing the M-Pesa part) the panel may not fit: let it scroll.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: SingleChildScrollView(
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
                    label: Text(_cart.discount > 0 ? tr('Punguzo :a', {'a': formatTsh(_cart.discount)}) : tr('Punguzo')),
                  ),
                  const Spacer(),
                  const T('Jumla ', style: TextStyle(color: mutedText)),
                  Text(formatTsh(_cart.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              if (_cart.isSplit) _buildSplit() else ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: T('Taslimu')),
                    ButtonSegment(value: 'mobile', label: T('Simu')),
                    ButtonSegment(value: 'insurance', label: T('Bima')),
                  ],
                  selected: {_cart.paymentMethod},
                  onSelectionChanged: _cart.canEdit ? (s) => _cart.setPaymentMethod(s.first) : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _cart.canEdit ? _cart.startSplit : null,
                    icon: const Icon(Icons.call_split, size: 18),
                    label: const T('Gawanya malipo'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: FilledButton(
                  // A split that doesn't add up can't be sent (the server would refuse it anyway).
                  onPressed: _submitting || (_cart.splitProblem != null && !_cart.uncertain) ? null : _completeSale,
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _cart.uncertain ? tr('Tuma tena · :a', {'a': formatTsh(_cart.total)}) : tr('Kamilisha mauzo · :a', {'a': formatTsh(_cart.total)}),
                          style: const TextStyle(fontSize: 17),
                        ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// Paid in parts: type every part except the last, which is "the rest".
  Widget _buildSplit() {
    final parts = _cart.split!;
    final sent = _cart.payments;
    final problem = _cart.splitProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(child: T('Malipo kwa njia zaidi ya moja', style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: _cart.canEdit ? _cart.endSplit : null, child: const T('Njia moja')),
        ]),
        for (var i = 0; i < parts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('method-$i-${parts.length}'),
                  initialValue: parts[i].method,
                  isDense: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [for (final m in Cart.methods) DropdownMenuItem(value: m, child: Text(paymentLabels[m] ?? m))],
                  onChanged: _cart.canEdit ? (m) => _cart.setSplitMethod(i, m!) : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: i < parts.length - 1
                    ? TextFormField(
                        key: ValueKey('amount-$i-${parts.length}'),
                        initialValue: parts[i].amount > 0 ? '${parts[i].amount}' : '',
                        enabled: _cart.canEdit,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, hintText: tr('kiasi')),
                        onChanged: (v) => _cart.setSplitAmount(i, int.tryParse(v) ?? 0),
                      )
                    // The last row: worked out, never typed.
                    : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatTsh(sent.last.amount), style: TextStyle(fontWeight: FontWeight.w700, color: sent.last.amount > 0 ? null : dangerRed)),
                        T('kinachobaki', style: const TextStyle(fontSize: 11, color: mutedText)),
                      ]),
              ),
              if (parts.length > 2)
                IconButton(
                  tooltip: tr('Ondoa'),
                  onPressed: _cart.canEdit ? () => _cart.removeSplitPart(i) : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ]),
          ),
        Row(children: [
          if (parts.length < Cart.methods.length)
            TextButton(onPressed: _cart.canEdit ? _cart.addSplitPart : null, child: const T('+ njia nyingine')),
          const Spacer(),
          if (problem != null)
            Flexible(
              child: Text(
                switch (problem) {
                  SplitProblem.missingAmount => tr('Weka kiasi kwa kila njia.'),
                  SplitProblem.overTotal => tr('Kiasi kimezidi jumla.'),
                  SplitProblem.sameMethodTwice => tr('Njia moja imerudiwa.'),
                },
                textAlign: TextAlign.right,
                style: const TextStyle(color: dangerRed, fontSize: 12),
              ),
            ),
        ]),
      ],
    );
  }
}
