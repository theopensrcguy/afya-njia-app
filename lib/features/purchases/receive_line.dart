import '../../core/units.dart';
import '../../models/product.dart';

/// One line of a delivery, as it arrived: "5 boksi of 100 at TSh 2,000 a boksi".
///
/// The packaging belongs to the delivery, not the product: the same Panadol
/// comes as a box of 100 from one supplier and a pack of 50 from another.
/// The server turns packs into base units (tablets) for stock.
class ReceiveLine {
  ReceiveLine({
    required this.product,
    required this.packName,
    required this.packSize,
    required this.packs,
    required this.packCost,
    required this.batch,
    required this.expiryYear,
    required this.expiryMonth,
  });

  final Product product;

  /// boksi, pakiti, kadi… (the base unit's name when packSize is 1).
  String packName;

  /// Base units in one pack: 100.
  int packSize;
  int packs;

  /// TSh for ONE pack, as on the invoice.
  int packCost;
  String batch;
  int expiryYear;
  int expiryMonth;

  int get quantity => packs * packSize;
  int get total => packs * packCost;

  /// "5 boksi (vidonge 100) = 50 kadi"
  String describe() {
    final base = product.units.isEmpty ? '' : product.units.first.name;
    final pack = packSize == 1 ? '$packs ${unitLabel(base, packs)}' : '$packs ${unitLabel(packName, packs)} (${unitLabel(base, packSize)} $packSize)';
    return packSize == 1 ? pack : '$pack = ${describeStock(quantity, product.units)}';
  }

  String get expiryText => '${expiryMonth.toString().padLeft(2, '0')}/$expiryYear';

  Map<String, dynamic> toJson() => {
        'product_id': product.id,
        'batch_number': batch,
        // As printed on the box: the server stores the last day of that month.
        'expiry_month': '$expiryYear-${expiryMonth.toString().padLeft(2, '0')}',
        'pack_name': packName,
        'pack_size': packSize,
        'packs': packs,
        'pack_cost': packCost,
      };
}
