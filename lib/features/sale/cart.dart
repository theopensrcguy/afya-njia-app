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
        'payment_method': paymentMethod,
        'discount': discount,
      };
}
