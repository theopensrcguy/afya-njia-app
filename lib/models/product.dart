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
      );
}
