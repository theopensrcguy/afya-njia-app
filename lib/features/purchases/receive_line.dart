import '../../core/units.dart';
import '../../models/product.dart';
import 'new_product.dart';

/// One line of a delivery, as it arrived: "5 boksi of 100 at TSh 2,000 a boksi".
///
/// The packaging belongs to the delivery, not the product: the same Panadol
/// comes as a box of 100 from one supplier and a pack of 50 from another.
/// The server turns packs into base units (tablets) for stock.
class ReceiveLine {
  ReceiveLine({
    required this.chosenProduct,
    required this.packName,
    required this.packSize,
    required this.packs,
    required this.packCost,
    required this.batch,
    required this.expiryYear,
    required this.expiryMonth,
    this.newProduct,
    this.linkCatalogueItemId,
    this.linkVariant,
  });

  /// The product picked on the line (for a new product, its first stand-in).
  final Product chosenProduct;

  /// For a new product, a stand-in made from the draft (see
  /// [NewProductDraft.asProduct]), so editing the draft updates every line.
  Product get product => newProduct?.asProduct() ?? chosenProduct;

  /// Set when this product arrives for the first time. Two lines of the same
  /// new product (two batches) share ONE draft object; the server creates it once.
  final NewProductDraft? newProduct;

  /// "Ndiyo, ni hiyo": the catalogue entry is this existing product's official name.
  final int? linkCatalogueItemId;
  final String? linkVariant;

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
        if (newProduct != null) 'new_product': newProduct!.toJson() else 'product_id': product.id,
        if (linkCatalogueItemId != null) 'link_catalogue_item_id': linkCatalogueItemId,
        if (linkVariant != null) 'link_variant': linkVariant,
        'batch_number': batch,
        // As printed on the box: the server stores the last day of that month.
        'expiry_month': '$expiryYear-${expiryMonth.toString().padLeft(2, '0')}',
        'pack_name': packName,
        'pack_size': packSize,
        'packs': packs,
        'pack_cost': packCost,
      };
}
