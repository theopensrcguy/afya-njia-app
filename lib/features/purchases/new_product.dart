import '../../models/product.dart';

/// One way the new product will be sold: "kadi = 10 vidonge, TSh 600".
/// [price] is null when the person may not set prices (the owner sets it
/// when confirming the delivery).
class DraftUnit {
  DraftUnit({required this.name, required this.baseQuantity, this.price});

  String name;
  int baseQuantity;
  int? price;

  Map<String, dynamic> toJson() => {
        'name': name,
        'base_quantity': baseQuantity,
        if (price != null) 'price': price,
      };
}

/// A product arriving for the first time, described on the delivery line.
///
/// Nothing is created on the phone: the server creates it when the delivery
/// is saved, with the name built from the catalogue entry (never typed),
/// unless it is an item outside the catalogue ([catalogueItemId] null).
class NewProductDraft {
  NewProductDraft({
    required this.name,
    required this.units,
    this.catalogueItemId,
    this.variant,
    this.source,
    this.brandName,
    this.reorderLevel = 0,
  });

  /// As it will be called. From the catalogue: shown, not editable.
  String name;
  final int? catalogueItemId;

  /// Which form/strength of a catalogue medicine: "Capsule 500mg".
  final String? variant;

  /// tmda | nemlit | supplies, for the "KUTOKA KATALOGI" label.
  final String? source;
  String? brandName;

  /// Smallest first; exactly one with baseQuantity 1 (stock is counted in it).
  List<DraftUnit> units;

  /// In base units.
  int reorderLevel;

  bool get offCatalogue => catalogueItemId == null;
  bool get hasPrices => units.every((u) => u.price != null);

  /// A stand-in Product so the rest of the delivery line (packaging, totals,
  /// describeStock) works the same for a new product as for an existing one.
  Product asProduct() => Product(
        id: 0,
        name: name,
        baseUnit: units.first.name,
        unitPrice: units.first.price ?? 0,
        onHand: 0,
        lowStock: false,
        units: [for (final u in units) ProductUnit(name: u.name, baseQuantity: u.baseQuantity, price: u.price ?? 0)],
      );

  Map<String, dynamic> toJson() => {
        if (catalogueItemId != null) 'catalogue_item_id': catalogueItemId,
        if (variant != null) 'variant': variant,
        if (catalogueItemId == null) 'name': name,
        if (brandName != null && brandName!.trim().isNotEmpty) 'brand_name': brandName!.trim(),
        'reorder_level': reorderLevel,
        'units': [for (final u in units) u.toJson()],
      };
}

/// What the "new product" screen hands back: either the draft, or "Ndiyo,
/// ni hiyo": an existing product, plus the catalogue entry to link to it.
class NewProductChoice {
  const NewProductChoice.draft(NewProductDraft this.draft)
      : existing = null,
        linkCatalogueItemId = null,
        linkVariant = null;

  const NewProductChoice.existing(Product this.existing, {this.linkCatalogueItemId, this.linkVariant}) : draft = null;

  final NewProductDraft? draft;
  final Product? existing;
  final int? linkCatalogueItemId;
  final String? linkVariant;
}
