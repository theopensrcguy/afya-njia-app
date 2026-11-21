import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session.dart';

/// The order basket kept on the phone (v0.48.1), shared by Agiza and Hisa
/// (v0.48.3): a product put in from the stock list is already there when
/// Agiza opens. One basket per person (and shop: a user id is per shop).
///
/// Entries: {line: the product as Agiza draws a line, skey: supplier list
/// it came from (0 = none yet), packs, pack: [name, size], to: supplier}.
class OrderBasket {
  static const _store = FlutterSecureStorage();

  /// How many products are in it: Hisa's basket pill listens to this.
  static final ValueNotifier<int> count = ValueNotifier(0);

  static String key(Session s) => 'agiza.cart.${s.user!.id}';

  static Future<List<Map<String, dynamic>>> read(Session s) async {
    try {
      final raw = await _store.read(key: key(s));
      final list = raw == null ? <Map<String, dynamic>>[] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      count.value = list.length;
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> write(Session s, List<Map<String, dynamic>> entries) async {
    count.value = entries.length;
    try {
      await _store.write(key: key(s), value: jsonEncode(entries));
    } catch (_) {
      // Storage refused: the basket lives until the app closes.
    }
  }

  /// A product from the stock list, as an Agiza line, in its biggest pack, 1 pack.
  static Map<String, dynamic> lineFromStock(Map<String, dynamic> p) {
    final units = ((p['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final big = units.isEmpty ? null : (units.toList()..sort((a, b) => ((b['base_quantity'] ?? 1) as num).compareTo((a['base_quantity'] ?? 1) as num))).first;
    return {
      'product_id': p['id'],
      'name': p['name'],
      'units': units,
      'on_hand': p['on_hand'] ?? 0,
      'days_left': null,
      'on_order': 0,
      'reason': p['is_out'] == true ? 'out' : (p['is_low'] == true ? 'low' : 'manual'),
      'pack_name': big?['name'] ?? p['base_unit'] ?? '',
      'pack_size': big?['base_quantity'] ?? 1,
      'pack_cost': null,
      'suggested_packs': null,
    };
  }

  /// Put a product in (or leave it if it's there). Returns the new count.
  static Future<int> addFromStock(Session s, Map<String, dynamic> p) async {
    final list = await read(s);
    final id = p['id'];
    if (!list.any((e) => (e['line'] as Map?)?['product_id'] == id)) {
      list.add({'line': lineFromStock(p), 'skey': 0, 'packs': 1});
      await write(s, list);
    }
    return list.length;
  }

  static Future<void> remove(Session s, Object? productId) async {
    final list = await read(s);
    list.removeWhere((e) => (e['line'] as Map?)?['product_id'] == productId);
    await write(s, list);
  }

  static Future<Set<int>> ids(Session s) async =>
      {for (final e in await read(s)) ((e['line'] as Map?)?['product_id'] as num?)?.toInt() ?? 0};
}
