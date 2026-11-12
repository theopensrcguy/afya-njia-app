import 'package:flutter/foundation.dart';

import '../../core/ids.dart';
import '../../models/product.dart';

/// One product in the basket, sold in ONE unit (kidonge, kadi or boksi).
/// [quantity] counts that unit: 2 kadi, not 20 tablets.
class CartLine {
  CartLine(this.product, this.unit, this.quantity);

  final Product product;
  ProductUnit unit;
  int quantity;

  int get lineTotal => unit.price * quantity;

  /// What leaves the shelf, in base units: 2 kadi of 10 = 20.
  int get baseQuantity => unit.baseQuantity * quantity;
}

/// One way of paying part of a sale: 15,000 by M-Pesa.
class PaymentPart {
  PaymentPart(this.method, [this.amount = 0]);

  String method; // cash | mobile | insurance
  int amount; // TSh; for the LAST row of a split it is worked out (the rest)
}

/// Why the payment can't be sent yet.
enum SplitProblem { missingAmount, overTotal, sameMethodTwice, needCustomer, customerNotApproved, overCreditLimit }

/// The basket for one sale, kept OUT of the screen on purpose.
///
/// Why separate: the rules (can't add more than is in stock, totals, building
/// the request) are plain Dart with no widgets, so they are easy to read and
/// easy to test. The screen only draws what the cart says.
///
/// The totals here are a preview for the person at the counter. The server
/// recalculates everything from its own prices; it never trusts these numbers.
class Cart extends ChangeNotifier {
  final Map<int, CartLine> _lines = {}; // product id -> line, keeps the order added

  String paymentMethod = 'cash'; // cash | mobile | insurance
  int discount = 0;

  /// Paid in parts (e.g. M-Pesa + cash), or null = all one way ([paymentMethod]).
  /// The person types every part except the LAST, which is always "the rest":
  /// so the parts add up to the total by construction, even when the
  /// discount or a quantity changes afterwards.
  List<PaymentPart>? split;

  static const methods = ['cash', 'mobile', 'insurance', 'credit'];

  /// Deni is offered only to someone allowed to sell on credit (set by the counter).
  bool creditAllowed = false;
  List<String> get allowedMethods => [for (final m in methods) if (m != 'credit' || creditAllowed) m];

  /// Who takes the credit part: {id, name, credit_status, available, owes} from GET customers.
  Map<String, dynamic>? customer;

  void setCustomer(Map<String, dynamic>? c) {
    if (!canEdit) return;
    customer = c;
    notifyListeners();
  }

  /// The part of this sale paid later (deni).
  int get creditDue => payments.where((p) => p.method == 'credit').fold<int>(0, (s, p) => s + p.amount);

  /// This sale's id, created on the phone. Sent with the sale so the server
  /// can recognise a retry. A new id is made only after a sale is confirmed.
  String saleId = randomId();

  /// True when we sent the sale but don't know if the server saved it
  /// (timeout, network dropped, server error). While true, the basket is
  /// FROZEN: the only way forward is to send exactly the same sale again.
  ///
  /// Why freeze: if the server did save it and the helper then adds an item
  /// and sends again, the server would return the OLD sale (same id) and the
  /// new item would silently go unrecorded. And if he cleared the basket,
  /// a sale that never arrived would be lost while the customer has the medicine.
  bool uncertain = false;

  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  bool get canEdit => !uncertain;
  int get itemCount => _lines.length;
  int get subtotal => _lines.values.fold(0, (sum, line) => sum + line.lineTotal);
  int get total => (subtotal - discount).clamp(0, subtotal);

  /// How many of the line's unit (2 kadi = 2). 0 if not in the basket.
  int quantityOf(int productId) => _lines[productId]?.quantity ?? 0;

  /// The unit this product is being sold in (null if not in the basket).
  ProductUnit? unitOf(int productId) => _lines[productId]?.unit;

  /// Most of [unit] the shelf allows: 336 tablets = 33 kadi of 10.
  static int maxOf(Product product, ProductUnit unit) => product.onHand ~/ unit.baseQuantity;

  /// Returns false if there isn't enough stock to add one more (or the basket is frozen).
  bool add(Product product, [int qty = 1]) {
    if (!canEdit) return false;
    final line = _lines[product.id];
    final unit = line?.unit ?? product.defaultUnit;
    final next = (line?.quantity ?? 0) + qty;
    if (next > maxOf(product, unit)) return false;
    _lines[product.id] = CartLine(product, unit, next);
    notifyListeners();
    return true;
  }

  /// Add [qty] of a chosen unit (a scan, a Haraka tile). If the product is
  /// already in the basket in another unit, that line switches to this unit
  /// and adds up, as long as the shelf allows it.
  bool addIn(Product product, ProductUnit unit, [int qty = 1]) {
    if (!canEdit) return false;
    final line = _lines[product.id];
    final same = line != null && line.unit.sameAs(unit);
    final next = (same ? line.quantity : 0) + qty;
    if (next > maxOf(product, unit)) return false;
    _lines[product.id] = CartLine(product, unit, next);
    _clampDiscount();
    notifyListeners();
    return true;
  }

  /// Switch kidonge ↔ kadi ↔ boksi. Keeps the number if the shelf allows it,
  /// otherwise lowers it to what's there. False if not even one fits.
  bool setUnit(int productId, ProductUnit unit) {
    if (!canEdit) return false;
    final line = _lines[productId];
    if (line == null) return false;
    final max = maxOf(line.product, unit);
    if (max == 0) return false;
    line.unit = unit;
    line.quantity = line.quantity.clamp(1, max);
    _clampDiscount();
    notifyListeners();
    return true;
  }

  /// Set an exact quantity (e.g. typed "21"). 0 removes the line.
  bool setQuantity(int productId, int qty) {
    if (!canEdit) return false;
    final line = _lines[productId];
    if (line == null) return false;
    if (qty <= 0) {
      _lines.remove(productId);
    } else if (qty > maxOf(line.product, line.unit)) {
      return false;
    } else {
      line.quantity = qty;
    }
    _clampDiscount();
    notifyListeners();
    return true;
  }

  void setPaymentMethod(String method) {
    if (!canEdit) return;
    paymentMethod = method;
    notifyListeners();
  }

  bool get isSplit => split != null;

  /// Start paying in parts. The usual case is "some by M-Pesa, the rest cash",
  /// so the typed row is the non-cash one and cash takes the rest.
  void startSplit() {
    if (!canEdit) return;
    split = paymentMethod == 'cash'
        ? [PaymentPart('mobile'), PaymentPart('cash')]
        : [PaymentPart(paymentMethod), PaymentPart('cash')];
    notifyListeners();
  }

  void endSplit() {
    if (!canEdit) return;
    split = null;
    notifyListeners();
  }

  void setSplitAmount(int i, int amount) {
    if (!canEdit || split == null || i >= split!.length - 1) return;
    split![i].amount = amount < 0 ? 0 : amount;
    notifyListeners();
  }

  void setSplitMethod(int i, String method) {
    if (!canEdit || split == null || i >= split!.length) return;
    split![i].method = method;
    notifyListeners();
  }

  /// A third way (e.g. insurance + M-Pesa + cash), typed, before "the rest".
  void addSplitPart() {
    if (!canEdit || split == null || split!.length >= allowedMethods.length) return;
    final used = split!.map((p) => p.method).toSet();
    split!.insert(split!.length - 1, PaymentPart(allowedMethods.firstWhere((m) => !used.contains(m))));
    notifyListeners();
  }

  void removeSplitPart(int i) {
    if (!canEdit || split == null || split!.length <= 2) return;
    split!.removeAt(i);
    notifyListeners();
  }

  /// The parts as they'd be sent; the last one gets whatever is left.
  List<PaymentPart> get payments {
    final parts = split;
    if (parts == null) return [PaymentPart(paymentMethod, total)];
    final typed = [for (final p in parts.take(parts.length - 1)) PaymentPart(p.method, p.amount)];
    final rest = total - typed.fold<int>(0, (s, p) => s + p.amount);
    return [...typed, PaymentPart(parts.last.method, rest)];
  }

  /// Null when the payment can be sent. The server checks the same again.
  SplitProblem? get splitProblem {
    if (split != null) {
      final ps = payments;
      if (ps.take(ps.length - 1).any((p) => p.amount <= 0)) return SplitProblem.missingAmount;
      if (ps.last.amount <= 0) return SplitProblem.overTotal;
      if (ps.map((p) => p.method).toSet().length != ps.length) return SplitProblem.sameMethodTwice;
    }
    // Deni: someone approved must take it, within what they may still owe.
    final credit = creditDue;
    if (credit > 0) {
      final c = customer;
      if (c == null) return SplitProblem.needCustomer;
      if (c['credit_status'] == 'blocked') return SplitProblem.customerNotApproved;
      final available = c['available'] as int?;
      if (available != null && credit > available) return SplitProblem.overCreditLimit;
    }
    return null;
  }

  void setDiscount(int value) {
    if (!canEdit) return;
    discount = value < 0 ? 0 : value;
    _clampDiscount();
    notifyListeners();
  }

  void _clampDiscount() {
    if (discount > subtotal) discount = subtotal;
  }

  /// We sent it, but the answer never came back.
  void markUncertain() {
    uncertain = true;
    notifyListeners();
  }

  /// The server answered "no" (e.g. not enough stock): nothing was saved,
  /// so the helper may fix the basket. The same id can be reused safely.
  void markRejected() {
    uncertain = false;
    notifyListeners();
  }

  /// The server confirmed the sale: start a fresh basket with a NEW id.
  void clear() {
    _lines.clear();
    discount = 0;
    paymentMethod = 'cash';
    split = null;
    customer = null;
    uncertain = false;
    saleId = randomId();
    notifyListeners();
  }

  /// The body for POST /api/sales.
  Map<String, dynamic> toRequest() => {
        'client_uuid': saleId,
        'items': [
          for (final line in _lines.values)
            {
              'product_id': line.product.id,
              'quantity': line.quantity,
              // The server charges this unit's price and takes quantity × size from stock.
              if (line.unit.id != null) 'unit_id': line.unit.id,
            },
        ],
        // Paid in parts: the server checks they add up to the total exactly.
        if (split != null)
          'payments': [for (final p in payments) {'method': p.method, 'amount': p.amount}]
        else
          'payment_method': paymentMethod,
        'discount': discount,
        if (creditDue > 0 && customer != null) 'customer_id': customer!['id'],
      };
}
