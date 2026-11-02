/// One way to sell a product: "kadi = 10 tablets for TSh 500".
///
/// Stock is counted in the smallest unit (baseQuantity 1). Sizes are per
/// product (a kadi of Coartem is 24), so nothing in the app assumes 10.
class ProductUnit {
  const ProductUnit({this.id, required this.name, required this.baseQuantity, required this.price});

  /// Null only for the stand-in base unit made for an older server.
  final int? id;
  final String name;
  final int baseQuantity;
  final int price; // TSh for ONE of this unit

  factory ProductUnit.fromJson(Map<String, dynamic> json) => ProductUnit(
        id: json['id'] as int?,
        name: json['name'] as String,
        baseQuantity: json['base_quantity'] as int,
        price: json['price'] as int,
      );

  bool sameAs(ProductUnit other) => id != null ? id == other.id : name == other.name;
}

/// A product as the counter sees it: name, price, and how much can be sold now.
///
/// [onHand] already excludes expired batches (the server works it out), so the
/// app never has to think about expiry when selling.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.baseUnit,
    required this.unitPrice,
    required this.onHand,
    required this.lowStock,
    this.nextExpiry,
    this.suggested = false,
    this.units = const [],
  });

  final int id;
  final String name;
  final String baseUnit;
  final int unitPrice; // TSh per base unit
  final int onHand; // sellable base units
  final bool lowStock;
  final DateTime? nextExpiry;

  /// True when the server offered this because the typed name looked like it
  /// ("parcetamol" -> Paracetamol), not because it matched. Shown under
  /// "Je, ulimaanisha...?" and never added to the basket without a tap.
  final bool suggested;

  /// Ways to sell it, smallest first. Never empty (see fromJson).
  final List<ProductUnit> units;

  /// What a tap adds: the smallest unit. One tap on "Kadi" switches it.
  ProductUnit get defaultUnit => units.first;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        name: json['name'] as String,
        baseUnit: json['base_unit'] as String,
        unitPrice: json['unit_price'] as int,
        onHand: json['on_hand'] as int,
        lowStock: json['low_stock'] as bool,
        nextExpiry: json['next_expiry'] == null ? null : DateTime.parse(json['next_expiry'] as String),
        // "== true" instead of a cast: an older server without this field still works.
        suggested: json['suggested'] == true,
        units: _units(json),
      );

  /// An older server sends no units: sell by the base unit at the base price.
  static List<ProductUnit> _units(Map<String, dynamic> json) {
    final list = ((json['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList();
    if (list.isNotEmpty) return list;
    return [ProductUnit(name: json['base_unit'] as String, baseQuantity: 1, price: json['unit_price'] as int)];
  }
}
