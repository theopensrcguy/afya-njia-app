import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/i18n.dart';
import '../../core/units.dart';

/// The shop's own unit names ("katoni", "dazeni"...), fetched once per app run.
/// A name added with "+ Kipimo kingine" is saved on the product or delivery
/// line, so the server offers it from then on (GET units).
List<String>? _shopUnits;

/// "Kipimo gani?": the standard units, then the shop's own, then
/// "+ Kipimo kingine" to type a new one. Returns the unit name (lowercase), or null.
Future<String?> pickUnitName(BuildContext context, {required ApiClient api, required String title}) async {
  if (_shopUnits == null) {
    try {
      final r = await api.get('units') as Map<String, dynamic>;
      _shopUnits = ((r['shop'] as List?) ?? const []).map((e) => '$e').toList();
    } on ApiException {
      _shopUnits = null; // offline: the standard list still works
    }
  }
  if (!context.mounted) return null;
  final shop = _shopUnits ?? const <String>[];
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: cardColor,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          for (final (n, label) in standardUnits) ListTile(title: Text(tr(label)), onTap: () => Navigator.of(sheet).pop(n)),
          if (shop.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: T('VYA DUKA LAKO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
            ),
          for (final n in shop) ListTile(title: Text(n), onTap: () => Navigator.of(sheet).pop(n)),
          ListTile(
            leading: const Icon(Icons.add, color: brandGreen),
            title: const T('Kipimo kingine…', style: TextStyle(color: brandGreen, fontWeight: FontWeight.w700)),
            subtitle: const T('mfano katoni, dazeni'),
            onTap: () => Navigator.of(sheet).pop('__new'),
          ),
        ]),
      ),
    ),
  );
  if (picked != '__new' || !context.mounted) return picked;
  final typed = await askText(context, title: tr('Kipimo kingine'), label: tr('Jina la kipimo (mfano katoni, dazeni)'), required: true);
  final name = normalUnitName(typed ?? '');
  if (name.isEmpty) return null;
  if (!standardUnits.any((u) => u.$1 == name) && !(_shopUnits?.contains(name) ?? false)) {
    (_shopUnits ??= []).add(name);
  }
  return name;
}
