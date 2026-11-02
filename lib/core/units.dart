import '../models/product.dart';
import 'format.dart';

/// Unit names in Swahili. Products imported from a spreadsheet may say
/// "tablet" or "strip"; units the owner types in the app are already Swahili
/// and are shown as typed.
const _labels = {
  'tablet': ('kidonge', 'vidonge'),
  'capsule': ('kidonge', 'vidonge'),
  'kidonge': ('kidonge', 'vidonge'),
  'vidonge': ('kidonge', 'vidonge'),
  'strip': ('kadi', 'kadi'),
  'blister': ('kadi', 'kadi'),
  'box': ('boksi', 'boksi'),
  'bottle': ('chupa', 'chupa'),
  'sachet': ('pakiti', 'pakiti'),
  'piece': ('kipande', 'vipande'),
  'kipande': ('kipande', 'vipande'),
};

/// The units a pharmacy sells by, offered as choices instead of free typing,
/// so the same thing always has the same name ("kadi", never "Kadi " or "strip")
/// and reports can add them up. "Nyingine…" exists for the rare odd one.
const standardUnits = [
  ('kidonge', 'Kidonge (tablet/capsule)'),
  ('kadi', 'Kadi (strip/blister)'),
  ('boksi', 'Boksi'),
  ('pakiti', 'Pakiti (sachet/packet)'),
  ('chupa', 'Chupa (bottle)'),
  ('tube', 'Tube'),
  ('sindano', 'Sindano (vial/ampoule)'),
  ('kopo', 'Kopo (tin/jar)'),
  ('kipande', 'Kipande (piece)'),
];

/// One spelling per unit: "  Kadi " -> "kadi", and the old English names from
/// the spreadsheet become the standard Swahili ones ("strip" -> "kadi").
String normalUnitName(String name) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  const english = {
    'tablet': 'kidonge', 'capsule': 'kidonge', 'vidonge': 'kidonge', 'strip': 'kadi', 'blister': 'kadi',
    'box': 'boksi', 'bottle': 'chupa', 'sachet': 'pakiti', 'piece': 'kipande', 'vipande': 'kipande',
  };
  return english[n] ?? n;
}

/// "kidonge" for 1, "vidonge" for more.
String unitLabel(String? name, [int count = 1]) {
  if (name == null || name.isEmpty) return '';
  final l = _labels[name.toLowerCase()];
  if (l == null) return name;
  return count == 1 ? l.$1 : l.$2;
}

/// Base units as people count them: "33 kadi + 6", "14 chupa", "8 vidonge".
///
/// Uses the product's smallest pack (the kadi), not the box: shelves are
/// counted in kadi, and "3 boksi + 3 kadi + 6" is harder to read.
String describeStock(int base, List<ProductUnit> units) {
  if (units.isEmpty) return '$base';
  final baseName = units.first.name;
  final packs = units.where((u) => u.baseQuantity > 1).toList();
  if (packs.isEmpty) return '$base ${unitLabel(baseName, base)}';

  final pack = packs.first;
  final n = base ~/ pack.baseQuantity;
  final rest = base % pack.baseQuantity;
  if (n == 0) return '$rest ${unitLabel(baseName, rest)}';
  return rest == 0 ? '$n ${unitLabel(pack.name, n)}' : '$n ${unitLabel(pack.name, n)} + $rest';
}

/// A sale's lines as the customer bought them.
///
/// The server stores one line per batch, in base units (FEFO can split "2 kadi"
/// into 12 + 8 tablets from two batches). Pieces of the same product and unit
/// are added back together and shown as sold: {name, quantity: 2, unit: "kadi", line_total}.
List<Map<String, dynamic>> mergeSaleItems(List items) {
  final merged = <String, Map<String, dynamic>>{};
  for (final raw in items.cast<Map>()) {
    final name = '${(raw['product'] as Map?)?['name'] ?? raw['name'] ?? '?'}';
    final unit = raw['unit_name'] as String?;
    final size = asInt(raw['unit_size']) == 0 ? 1 : asInt(raw['unit_size']);
    final key = '$name|$unit|$size';
    final m = merged.putIfAbsent(key, () => {'name': name, 'unit': unit, 'size': size, 'base': 0, 'line_total': 0});
    m['base'] = (m['base'] as int) + asInt(raw['quantity']);
    m['line_total'] = (m['line_total'] as int) + asInt(raw['line_total']);
  }
  return [
    for (final m in merged.values)
      {'name': m['name'], 'unit': m['unit'], 'quantity': (m['base'] as int) ~/ (m['size'] as int), 'line_total': m['line_total']},
  ];
}
