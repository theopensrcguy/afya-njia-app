import '../../models/product.dart';

/// Which unit a scan or a Haraka tile should add.
///
/// 1. The unit it usually sells in (from the shop's own sales).
/// 2. What the scanned code is printed on, EXCEPT the biggest pack: a box
///    barcode is how people find the kadi inside, and selling a whole box is
///    the rarer case.
/// 3. Otherwise the middle unit when there is one (kidonge · KADI · boksi),
///    else the smallest (PAKITI · boksi for ORS).
/// One tap on the unit chips changes it, so a wrong guess costs one tap.
ProductUnit pickSellUnit(Product p, {String? usual, String? printedOn}) {
  ProductUnit? named(String? n) {
    if (n == null || n.isEmpty) return null;
    for (final u in p.units) {
      if (u.name == n) return u;
    }
    return null;
  }

  final fromSales = named(usual);
  if (fromSales != null) return fromSales;

  final packs = p.units.where((u) => u.baseQuantity > 1).toList(); // smallest first
  final biggest = packs.isEmpty ? null : packs.last;
  final printed = named(printedOn);
  if (printed != null && (biggest == null || !printed.sameAs(biggest))) return printed;

  return packs.length >= 2 ? packs.first : p.defaultUnit;
}
