import 'package:flutter/foundation.dart';

import '../../core/ids.dart';
import '../../models/product.dart';

class CartLine {
  CartLine(this.product, this.quantity);

  final Product product;
  int quantity;

  int get lineTotal => product.unitPrice * quantity;
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

  int quantityOf(int productId) => _lines[productId]?.quantity ?? 0;

  /// Returns false if there isn't enough stock to add one more (or the basket is frozen).
  bool add(Product product, [int qty = 1]) {
    if (!canEdit) return false;
    final current = quantityOf(product.id);
    if (current + qty > product.onHand) return false;
    _lines[product.id] = CartLine(product, current + qty);
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
    } else if (qty > line.product.onHand) {
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
          for (final line in _lines.values) {'product_id': line.product.id, 'quantity': line.quantity},
        ],
        'payment_method': paymentMethod,
        'discount': discount,
      };
}
