import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../purchases/new_product.dart';
import '../purchases/new_product_screen.dart';
import 'order_send_screen.dart';
import 'orders_screen.dart';
import 'shopping_list_screen.dart';
import '../../core/order_basket.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n.dart';

/// Agiza: what will run out before the next delivery, grouped by supplier.
///
/// Three views of the same stock: suggested (runs out before the next
/// delivery), alerts (out, or at the reorder level) and all stock, because
/// ordering is the person's decision: anything can be ordered, even what
/// isn't running out. Only suggested lines come with an amount.
///
/// The server suggests (from the shop's own sales and deliveries); the person
/// decides: how far ahead to order, how many, in which packaging (strips last
/// time, boxes now that business has grown), and any other product they want.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.session, this.draftId});

  final Session session;

  /// Continue a draft (rasimu) where it was left: its products on top, the
  /// shop's lists below to add more from, then save again or send.
  final int? draftId;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  static const _covers = [(7, 'Wiki 1'), (14, 'Wiki 2'), (30, 'Mwezi 1')];
  // v0.48: what's needed (out, low, runs out, asked for: one list), what customers asked for, everything.
  static const _views = [('needed', 'Zinahitajika'), ('requests', 'Wanaouliza'), ('all', 'Zote')];

  int _cover = 14;
  String _view = 'needed';

  /// Taken off this list ("× / swipe"): hidden at once, "not this time" for 7 days on the server.
  final Set<int> _hidden = {};

  /// Bajeti: the most a trip or an order may cost. What sells most and is out stays; the rest drops to 0.
  int? _budget;
  final Set<int> _trimmed = {};

  /// Supplier cards folded shut (by supplier id, 0 = none).
  final Set<int> _folded = {};
  int _lists = 0; // buying trips still open

  // v0.48.1: the order basket. The list is the shelf; what's chosen goes in here,
  // grouped by supplier, and leaves as WhatsApp orders, a buying trip or a saved list.
  // Product id → {line: the line as added, skey: the supplier list it came from}.
  final Map<int, Map<String, dynamic>> _cart = {};
  final Map<int, Map<String, dynamic>> _trimmedOut = {}; // taken out by the budget, back when it's removed
  bool _picking = false; // hold a row: tick several, one action
  /// How this basket was started (v0.48.4): null (not yet), 'suggested' or 'own'.
  /// The two start cards turn into a strip that says it, instead of just vanishing.
  String? _startMode;

  /// A suggestion emptied by hand is no longer "in the basket": the cards come back.
  String? get _mode => _startMode == 'suggested' && _cart.isEmpty ? null : _startMode;
  final _filterFocus = FocusNode();
  final Set<int> _selected = {};

  final _filter = TextEditingController(); // "Zote" can be long
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _open = []; // orders sent, not yet delivered
  String? _error;
  bool _loading = true;

  // The person's choices, by product id.
  final Map<int, int> _packs = {};
  final Map<int, (String, int)> _packOf = {}; // packaging chosen instead of the usual one
  final Map<int, List<Map<String, dynamic>>> _extra = {}; // supplier id (0 = none) → products added by hand
  final Map<int, int> _supplierOf = {}; // product id → supplier chosen for it (0 = none yet)

  // The draft being continued (null: a new order).
  Map<String, dynamic>? _draft;
  final List<Map<String, dynamic>> _draftLines = [];
  int _draftSupplier = 0;
  bool _savingDraft = false;
  bool _justSaved = false; // the floating button says "Imehifadhiwa ✓" for a moment
  String _draftSaved = ''; // what the draft looked like when last loaded or saved

  /// Products, amounts, packaging and supplier: changed since the last save?
  String get _draftSig =>
      '${_draftChosen.map((l) => '${l['product_id']}:${l['packs']}:${l['pack_name']}:${l['pack_size']}:${l['supplier_id']}').join(',')}|$_draftSupplier';
  bool get _draftChanged => _draft != null && _draftSig != _draftSaved;

  ApiClient get _api => widget.session.api;
  bool get _costs => widget.session.user!.can(Perm.viewCosts);
  bool get _canCreate => widget.session.user!.can(Perm.createProducts);

  @override
  void initState() {
    super.initState();
    _restoreCart();
    _load();
  }

  /// The basket outlives the screen and the app: an order is built over a day.
  Future<void> _restoreCart() async {
    try {
      final list = await OrderBasket.read(widget.session);
      if (list.isEmpty || !mounted) return;
      setState(() {
        for (final e in list) {
          final l = (e['line'] as Map).cast<String, dynamic>();
          final id = asInt(l['product_id']);
          _cart[id] = {'line': l, 'skey': asInt(e['skey'])};
          if (e['packs'] != null) _packs[id] = asInt(e['packs']);
          if (e['pack'] is List) _packOf[id] = ('${(e['pack'] as List)[0]}', asInt((e['pack'] as List)[1]));
          if (e['to'] != null) _supplierOf[id] = asInt(e['to']);
        }
      });
    } catch (_) {
      // A basket from an older version, or storage refused: start empty.
    }
  }

  void _saveCart() {
    final list = [
      for (final MapEntry(key: id, value: e) in _cart.entries)
        {
          'line': e['line'],
          'skey': e['skey'],
          'packs': _packs[id],
          if (_packOf[id] != null) 'pack': [_packOf[id]!.$1, _packOf[id]!.$2],
          if (_supplierOf[id] != null) 'to': _supplierOf[id],
        },
    ];
    OrderBasket.write(widget.session, list);
  }

  int _suggest(Map<String, dynamic> l) => asInt(l['suggested_packs']) > 0 ? asInt(l['suggested_packs']) : 1;

  /// Into the basket, with the suggested amount (or what was already typed).
  void _put(Map<String, dynamic> l, int supplierKey) {
    final id = asInt(l['product_id']);
    _cart[id] = {'line': Map<String, dynamic>.of(l), 'skey': supplierKey};
    if ((_packs[id] ?? 0) <= 0) _packs[id] = _suggest(l);
    _trimmed.remove(id);
  }

  void _take(int id) {
    _cart.remove(id);
    _packs.remove(id);
    _packOf.remove(id);
  }

  int _keyOf(int id) => _supplierOf[id] ?? asInt(_cart[id]?['skey']);

  /// The basket by supplier (0 = none yet), in the order things were added.
  Map<int, List<Map<String, dynamic>>> get _cartGroups {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final MapEntry(key: id, value: e) in _cart.entries) {
      (out[_keyOf(id)] ??= []).add((e['line'] as Map).cast<String, dynamic>());
    }
    return out;
  }

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _counts => ((_data?['counts'] as Map?) ?? const {}).cast<String, dynamic>();
  int get _drafts => asInt(_data?['drafts']);

  /// [fresh]: a new period means new suggestions, so amounts the person typed
  /// are dropped (what was added by hand stays). Switching views keeps them.
  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.draftId != null && !_draftGone) {
        if (_draft == null) {
          await _loadDraft();
        } else {
          await _checkDraft();
        }
      }
      final d = await _api.get('reorder', query: {'cover': '$_cover', 'view': _view}) as Map<String, dynamic>;
      final open = (await _api.get('purchase-orders') as List).cast<Map<String, dynamic>>();
      var lists = _lists;
      try {
        lists = (((await _api.get('shopping-lists') as Map)['lists'] as List?) ?? const []).length;
      } on ApiException {
        // An older server: no buying trips yet.
      }
      if (!mounted) return;
      setState(() {
        _data = d;
        _open = open;
        _lists = lists;
        _hidden.clear(); // the server now leaves out what was put aside
        // From Hisa (v0.48.3) a product comes with no supplier or last price: take them from here.
        for (final g in ((d['groups'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          final k = asInt((g['supplier'] as Map?)?['id']);
          for (final l in ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
            final e = _cart[asInt(l['product_id'])];
            if (e == null) continue;
            if (asInt(e['skey']) == 0 && k != 0) e['skey'] = k;
            final line = (e['line'] as Map).cast<String, dynamic>();
            if (line['pack_cost'] == null && l['pack_cost'] != null && '${line['pack_name']}' == '${l['pack_name']}') {
              e['line'] = {...line, 'pack_cost': l['pack_cost'], 'pack_size': l['pack_size']};
            }
          }
        }
        if (fresh) {
          _packs.removeWhere((id, _) => !_isExtra(id) && !_cart.containsKey(id) && !_inDraft(id));
          _packOf.removeWhere((id, _) => !_isExtra(id) && !_cart.containsKey(id) && !_inDraft(id));
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The draft was deleted or sent somewhere else (Maagizo, the drafts list,
  /// another phone): this screen stops showing it (v0.47.1).
  bool _draftGone = false;

  void _forgetDraft(String why) {
    setState(() {
      _draftGone = true;
      _draft = null;
      _draftLines.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(why)));
  }

  /// Still a draft? (Coming back from Maagizo, where it may have been deleted or sent.)
  Future<void> _checkDraft() async {
    try {
      final o = await _api.get('purchase-orders/${widget.draftId}') as Map<String, dynamic>;
      if (o['status'] != 'draft' && mounted) _forgetDraft(tr('Rasimu hii imeshatumwa.'));
    } on ApiException catch (e) {
      if (e.status == 404 && mounted) _forgetDraft(tr('Rasimu hii imefutwa.'));
    }
  }

  /// Delete the open draft (asks first), then leave it.
  Future<void> _deleteDraft() async {
    final ok = await confirmDialog(context,
        title: tr('Futa rasimu hii?'),
        message: tr('Bidhaa :n zitaondoka kwenye rasimu. Hisa haibadiliki.', {'n': _draftLines.length}),
        confirm: tr('Futa rasimu'),
        danger: true);
    if (ok != true || !mounted) return;
    try {
      await _api.delete('purchase-orders/${widget.draftId}');
      if (!mounted) return;
      _draftSaved = _draftSig; // nothing left to save: leave without asking
      _forgetDraft(tr('Rasimu imefutwa.'));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteOtherDraft(int id) async {
    final ok = await confirmDialog(context, title: tr('Futa rasimu hii?'), message: tr('Hisa haibadiliki.'), confirm: tr('Futa rasimu'), danger: true);
    if (ok != true || !mounted) return;
    try {
      await _api.delete('purchase-orders/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Rasimu imefutwa.'))));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The draft's products become lines like any other (same amount/packaging controls).
  Future<void> _loadDraft() async {
    Map<String, dynamic>? found;
    try {
      found = await _api.get('purchase-orders/${widget.draftId}') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    if (found == null) {
      _draftGone = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Rasimu hii imefutwa.'))));
      return;
    }
    final o = found;
    if (o['status'] != 'draft') {
      throw ApiException(tr('Agizo hili limeshatumwa; haliwezi kubadilishwa.'));
    }
    _draft = o;
    _draftSupplier = asInt((o['supplier'] as Map?)?['id']);
    _draftLines
      ..clear()
      ..addAll([
        for (final l in ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>())
          {
            'product_id': l['product_id'],
            'name': l['product'],
            'units': l['units'] ?? const [],
            'on_hand': l['on_hand'] ?? 0,
            'days_left': null,
            'on_order': 0,
            'reason': 'draft',
            'pack_name': l['pack_name'],
            'pack_size': l['pack_size'],
            'pack_cost': null,
            'suggested_packs': null,
            // Each product of a draft goes to its own supplier (null: the draft's).
            'supplier_id': asInt(l['supplier_id'] ?? (o['supplier'] as Map?)?['id']),
          },
      ]);
    for (final l in ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      _packs[asInt(l['product_id'])] = asInt(l['packs']);
    }
    _draftSaved = _draftSig;
  }

  /// Leaving with changes not saved: save them, drop them, or stay.
  Future<void> _confirmLeave() async {
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const T('Hifadhi mabadiliko ya rasimu?'),
        content: const T('Umebadilisha rasimu hii bila kuihifadhi.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop('stay'), child: const T('Baki')),
          TextButton(onPressed: () => Navigator.of(d).pop('drop'), child: const T('Toka bila kuhifadhi', style: TextStyle(color: dangerRed))),
          FilledButton(onPressed: () => Navigator.of(d).pop('save'), child: const T('Hifadhi')),
        ],
      ),
    );
    if (!mounted || v == null || v == 'stay') return;
    if (v == 'save') {
      await _saveDraft();
      if (!mounted || _draftChanged) return; // not saved (error shown): stay
    }
    Navigator.of(context).pop(true);
  }

  bool _inDraft(int productId) => _draftLines.any((l) => asInt(l['product_id']) == productId);

  List<Map<String, dynamic>> get _draftChosen => [
        for (final l in _draftLines)
          if (_chosen(l) > 0) {...l, 'pack_name': _pack(l).$1, 'pack_size': _pack(l).$2, 'packs': _chosen(l)},
      ];

  /// Save the draft as it is now, and stay on it. Returns whether it was saved.
  Future<bool> _saveDraft({bool quiet = false}) async {
    final lines = _draftChosen;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Chagua angalau bidhaa moja yenye idadi.'))));
      return false;
    }
    setState(() => _savingDraft = true);
    try {
      await _api.patch('purchase-orders/${widget.draftId}', {
        'supplier_id': _draftSupplier == 0 ? null : _draftSupplier,
        'cover_days': asInt(_draft?['cover_days']) == 0 ? _cover : asInt(_draft?['cover_days']),
        'draft': true,
        'lines': [
          for (final l in lines)
            {
              'product_id': asInt(l['product_id']),
              'pack_name': l['pack_name'],
              'pack_size': asInt(l['pack_size']),
              'packs': asInt(l['packs']),
              'supplier_id': asInt(l['supplier_id']) == 0 ? null : asInt(l['supplier_id']),
            },
        ],
      });
      if (!mounted) return false;
      setState(() {
        _draftLines.removeWhere((l) => _chosen(l) == 0); // 0 = taken out
        _draftSaved = _draftSig;
      });
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Rasimu imehifadhiwa. Endelea sasa, au baadaye kupitia Maagizo.'))));
      }
      return true;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  /// Send one supplier's part of the draft: everything is saved first, then
  /// the order screen sends just these products as that supplier's order.
  /// The other parts stay in the draft; an emptied draft is gone.
  Future<void> _sendDraftPart(int supplierKey) async {
    final lines = _draftChosen.where((l) => asInt(l['supplier_id']) == supplierKey).toList();
    if (lines.isEmpty) return;
    if (_draftChanged && !await _saveDraft(quiet: true)) return;
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderSendScreen(
        session: widget.session,
        supplier: _supplierById(supplierKey),
        suppliers: _suppliers,
        cover: asInt(_draft?['cover_days']) == 0 ? _cover : asInt(_draft?['cover_days']),
        lines: lines,
        orderId: widget.draftId,
        draftPart: true,
      ),
    ));
    if (done != true || !mounted) return;
    try {
      await _api.get('purchase-orders/${widget.draftId}'); // still there: some of it is left
      if (!mounted) return;
      setState(() => _draft = null);
      _load();
    } on ApiException {
      if (mounted) Navigator.of(context).pop(true); // all sent: the draft is gone
    }
  }

  bool _isExtra(int productId) => _extra.values.any((ls) => ls.any((l) => asInt(l['product_id']) == productId));

  List<Map<String, dynamic>> get _suppliers => ((_data?['suppliers'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Server groups plus products added by hand (in their supplier's group,
  /// or a new group for a supplier that had nothing suggested).
  /// Server groups plus products added by hand, then regrouped by the
  /// supplier the person chose for each line ("Kutoka:"): one supplier can't
  /// have everything, and each supplier still gets one order with only theirs.
  List<Map<String, dynamic>> get _groups {
    final q = _filter.text.trim().toLowerCase();
    bool shown(Map<String, dynamic> l) => !_hidden.contains(asInt(l['product_id'])) && (q.isEmpty || '${l['name']}'.toLowerCase().contains(q));
    final meta = <int, Map<String, dynamic>>{};
    final entries = <(int, Map<String, dynamic>)>[];
    final ids = <int>{};
    for (final g in ((_data?['groups'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final key = asInt((g['supplier'] as Map?)?['id']);
      meta[key] = g;
      for (final l in ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        ids.add(asInt(l['product_id']));
        if (shown(l) && !_inDraft(asInt(l['product_id']))) entries.add((key, l));
      }
    }
    for (final e in _extra.entries) {
      for (final l in e.value) {
        if (!ids.contains(asInt(l['product_id'])) && shown(l) && !_inDraft(asInt(l['product_id']))) entries.add((e.key, l));
      }
    }
    final byKey = <int, List<Map<String, dynamic>>>{};
    for (final k in meta.keys) {
      byKey[k] = [];
    }
    for (final (key, l) in entries) {
      (byKey[_supplierOf[asInt(l['product_id'])] ?? key] ??= []).add(l);
    }
    return [
      for (final MapEntry(key: k, value: lines) in byKey.entries)
        if (lines.isNotEmpty)
          meta[k] != null
              ? {...meta[k]!, 'lines': lines}
              : {'supplier': _supplierById(k), 'lines': lines, 'lead_days': null},
    ];
  }

  /// The list's menu: the same supplier for every product in it (each can
  /// still be changed under its name), or choose / clear every product.
  Future<void> _groupAction(String action, List<Map<String, dynamic>> lines, int current) async {
    if (action == 'todraft') {
      final picked = lines.where((l) => _chosen(l) > 0).toList();
      if (picked.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Chagua angalau bidhaa moja yenye idadi.'))));
        return;
      }
      setState(() => _draftLines.addAll([for (final l in picked) {...l, 'supplier_id': current}]));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Bidhaa :n zimewekwa kwenye rasimu. Kumbuka kuihifadhi.', {'n': picked.length})),
      ));
      return;
    }
    if (action == 'supplier') {
      final k = await _askSupplier(tr('Agiza bidhaa :n kutoka kwa nani?', {'n': lines.length}), current);
      if (k == null || k == current || !mounted) return;
      setState(() {
        for (final l in lines) {
          _supplierOf[asInt(l['product_id'])] = k;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Bidhaa :n zitaagizwa kutoka :supplier.', {'n': lines.length, 'supplier': _supplierById(k)?['name'] ?? tr('msambazaji utakayemchagua')})),
      ));
      return;
    }
    setState(() {
      for (final l in lines) {
        // "Weka zote kikapuni" / "Toa zote kikapuni".
        action == 'none' ? _take(asInt(l['product_id'])) : _put(l, current);
      }
    });
    _saveCart();
  }

  Map<String, dynamic>? _supplierById(int id) =>
      id == 0 ? null : _suppliers.firstWhere((x) => asInt(x['id']) == id, orElse: () => {'id': id, 'name': '?'});

  Future<int?> _askSupplier(String title, int current) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cardColor,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              for (final s in _suppliers)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text('${s['name']}'),
                  trailing: asInt(s['id']) == current ? const Icon(Icons.check, color: brandGreen) : null,
                  onTap: () => Navigator.of(sheet).pop(asInt(s['id'])),
                ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const T('Bila msambazaji'),
                subtitle: const T('Utachagua ukituma'),
                trailing: current == 0 ? const Icon(Icons.check, color: brandGreen) : null,
                onTap: () => Navigator.of(sheet).pop(0),
              ),
            ]),
          ),
        ),
      );

  /// "Kutoka:": order this product from another supplier (or decide later).
  Future<void> _moveLine(Map<String, dynamic> l, int current) async {
    final k = await _askSupplier(tr('Agiza :a kutoka kwa nani?', {'a': l['name']}), current);
    if (k == null || k == current || !mounted) return;
    setState(() => _supplierOf[asInt(l['product_id'])] = k);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(':name itaagizwa kutoka :supplier.', {'name': l['name'], 'supplier': _supplierById(k)?['name'] ?? tr('msambazaji utakayemchagua')})),
    ));
  }

  (String, int) _pack(Map<String, dynamic> l) =>
      _packOf[asInt(l['product_id'])] ?? ('${l['pack_name']}', asInt(l['pack_size']) < 1 ? 1 : asInt(l['pack_size']));

  /// What will be ordered: a draft's own amount, or the basket's. Not in the basket = 0.
  int _chosen(Map<String, dynamic> l) {
    final id = asInt(l['product_id']);
    if (_inDraft(id)) return _packs[id] ?? 0;
    if (_cart.containsKey(id)) return _packs[id] ?? _suggest(l);
    return 0;
  }

  List<ProductUnit> _units(Map<String, dynamic> l) =>
      [for (final u in ((l['units'] as List?) ?? const []).cast<Map<String, dynamic>>()) ProductUnit.fromJson(u)];

  // ------------------------------------------------------------- packaging

  /// Order in another packaging. The amount is converted so it stays about
  /// the same number of tablets: 6 kadi of 10 → 1 boksi of 100 (rounded up).
  Future<void> _choosePack(Map<String, dynamic> l) async {
    final units = _units(l);
    final (curName, curSize) = _pack(l);
    final options = <(String, int)>[
      for (final u in units) (u.name, u.baseQuantity),
      if (!units.any((u) => u.name == '${l['pack_name']}' && u.baseQuantity == asInt(l['pack_size'])))
        ('${l['pack_name']}', asInt(l['pack_size'])),
    ];
    final base = units.isEmpty ? '' : units.first.name;
    final picked = await showModalBottomSheet<(String, int)?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Agiza :a kwa:', {'a': l['name']}), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final (n, size) in options)
              ListTile(
                title: Text(unitLabel(n), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: size > 1 ? Text('${unitLabel(base, size)} $size') : null,
                trailing: n == curName && size == curSize ? const Icon(Icons.check, color: brandGreen) : null,
                onTap: () => Navigator.of(sheet).pop((n, size)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const T('Kifungashio kingine…'),
              subtitle: const T('mfano: katoni ya boksi 10'),
              onTap: () => Navigator.of(sheet).pop(('', 0)),
            ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    var (name, size) = picked;
    if (size == 0) {
      // A packaging this product never had: name it, then how many base units are inside.
      final n = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cardColor,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (id, label) in standardUnits) ListTile(title: Text(label), onTap: () => Navigator.of(sheet).pop(id)),
            ]),
          ),
        ),
      );
      if (n == null || !mounted) return;
      final v = await askText(context,
          title: tr(':a moja ina :b ngapi?', {'a': unitLabel(n), 'b': unitLabel(base, 2)}), label: tr('Idadi'), digitsOnly: true, required: true);
      final s = int.tryParse(v ?? '') ?? 0;
      if (s < 1 || !mounted) return;
      (name, size) = (n, s);
    }
    final baseQty = _chosen(l) * curSize;
    setState(() {
      _packOf[asInt(l['product_id'])] = (name, size);
      _packs[asInt(l['product_id'])] = baseQty == 0 ? 1 : (baseQty / size).ceil();
    });
  }

  // ------------------------------------------------------------- any product

  Future<void> _orderAnything() async {
    final key = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: T('Agiza kutoka kwa nani?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final s in _suppliers)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${s['name']}'),
                onTap: () => Navigator.of(sheet).pop(asInt(s['id'])),
              ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const T('Bado sijaamua'),
              subtitle: const T('Utachagua ukituma'),
              onTap: () => Navigator.of(sheet).pop(0),
            ),
          ]),
        ),
      ),
    );
    if (key != null && mounted) await _addProduct(key);
  }

  Future<void> _addProduct(int supplierKey, {bool toDraft = false}) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (_) => _ProductPickSheet(api: _api, canCreate: _canCreate),
    );
    if (picked == null || !mounted) return;
    // "+ Bidhaa mpya": a product the shop doesn't have yet, made first (no stock), then ordered.
    final List<Product> chosen;
    if (picked is String) {
      final made = await _createProduct(picked);
      if (made == null || !mounted) return;
      chosen = [made];
    } else {
      chosen = (picked as List).cast<Product>();
    }
    final skipped = <String>[];
    setState(() {
      for (final p in chosen) {
        final already = _inDraft(p.id) ||
            (!toDraft && _groups.expand((g) => (g['lines'] as List).cast<Map<String, dynamic>>()).any((l) => asInt(l['product_id']) == p.id)) ||
            (_extra[supplierKey] ?? const []).any((l) => asInt(l['product_id']) == p.id);
        if (already) {
          skipped.add(p.name);
          continue;
        }
        final biggest = p.units.isEmpty ? null : p.units.last;
        final line = <String, dynamic>{
          if (toDraft) 'supplier_id': supplierKey,
          'product_id': p.id,
          'name': p.name,
          'units': [for (final u in p.units) {'name': u.name, 'base_quantity': u.baseQuantity, 'price': u.price}],
          'on_hand': p.onHand,
          'days_left': null,
          'on_order': 0,
          'reason': 'manual',
          'pack_name': biggest?.name ?? p.baseUnit,
          'pack_size': biggest?.baseQuantity ?? 1,
          'pack_cost': null,
          'suggested_packs': null,
        };
        (toDraft ? _draftLines : (_extra[supplierKey] ??= [])).add(line);
        _packs[p.id] = 1;
        if (!toDraft) _put(line, supplierKey); // added by hand = wanted: straight into the basket
      }
    });
    _saveCart();
    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(':name tayari iko kwenye orodha.', {'name': skipped.join(', ')}))));
    }
  }

  /// The same form as a new product in a delivery (catalogue name, brand,
  /// units, prices); saved at once, with no stock, so it can be ordered.
  Future<Product?> _createProduct(String typed) async {
    final choice = await Navigator.of(context).push<NewProductChoice>(MaterialPageRoute(
      builder: (_) => NewProductScreen(api: _api, canPrice: widget.session.user!.can(Perm.editPrices), typedName: typed),
    ));
    if (choice == null || !mounted) return null;
    if (choice.existing != null) return choice.existing;
    try {
      final r = await _api.post('products/new', choice.draft!.toJson()) as Map<String, dynamic>;
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(':name imeongezwa kwenye bidhaa zako.', {'name': r['name']}))));
      return Product.fromJson({'unit_price': 0, 'low_stock': false, ...r});
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    }
  }

  /// The floating button's list: every draft, and "Endelea kuhariri" on each.
  Future<void> _showDrafts() async {
    List<Map<String, dynamic>> list = [];
    try {
      list = (await _api.get('purchase-orders', query: {'status': 'draft'}) as List).cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final open = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
            Row(children: [
              const Expanded(child: T('Rasimu zako', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _openOrders('draft');
                },
                child: const T('Zote kwenye Maagizo'),
              ),
            ]),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: T('Hakuna rasimu.', style: TextStyle(color: mutedText))),
            for (final o in list)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: asInt(o['id']) == widget.draftId ? const Color(0xFFF1F5FC) : pageBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: asInt(o['id']) == widget.draftId ? Border.all(color: const Color(0xFF2F5FA8)) : null,
                ),
                child: Row(children: [
                  Expanded(child: _draftSummary(o)),
                  // Delete straight from the list (v0.47.1).
                  IconButton(
                    tooltip: tr('Futa rasimu'),
                    icon: const Icon(Icons.delete_outline_rounded, color: dangerRed),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      asInt(o['id']) == widget.draftId ? _deleteDraft() : _deleteOtherDraft(asInt(o['id']));
                    },
                  ),
                  asInt(o['id']) == widget.draftId
                      ? const T('Unaihariri sasa', style: TextStyle(fontSize: 12, color: Color(0xFF2F5FA8), fontWeight: FontWeight.w800))
                      : FilledButton(
                          onPressed: () => Navigator.of(sheet).pop(asInt(o['id'])),
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const T('Endelea kuhariri'),
                        ),
                ]),
              ),
          ]),
        ),
      ),
    );
    if (open == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReorderScreen(session: widget.session, draftId: open)));
    if (mounted) _load();
  }

  /// "Jumla, Shelys · bidhaa 4 · dakika 5 zilizopita" and its first products.
  Widget _draftSummary(Map<String, dynamic> o) {
    final lines = ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final names = {
      for (final l in lines) _supplierById(asInt(l['supplier_id'] ?? (o['supplier'] as Map?)?['id']))?['name'] ?? tr('Bila msambazaji'),
    };
    final at = DateTime.tryParse('${o['updated_at'] ?? ''}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(names.join(', '), style: const TextStyle(fontWeight: FontWeight.w800)),
      Text('${tr('bidhaa :n', {'n': lines.length})}${at == null ? '' : ' · ${timeAgo(at)}'}', style: const TextStyle(fontSize: 12, color: mutedText)),
      Text('${lines.take(3).map((l) => l['product']).join(', ')}${lines.length > 3 ? '…' : ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    ]);
  }

  Future<void> _openOrders(String status) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrdersScreen(session: widget.session, status: status, suppliers: _suppliers)));
    if (mounted) _load();
  }

  // ------------------------------------------------------------- send / open orders

  Future<void> _send(Map<String, dynamic> g) async {
    final lines = ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final chosen = [
      for (final l in lines)
        if (_chosen(l) > 0) {...l, 'pack_name': _pack(l).$1, 'pack_size': _pack(l).$2, 'packs': _chosen(l)},
    ];
    if (chosen.isEmpty) return;
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderSendScreen(
        session: widget.session,
        supplier: g['supplier'] as Map<String, dynamic>?,
        suppliers: _suppliers,
        cover: _cover,
        lines: chosen,
      ),
    ));
    if (sent == true && mounted) {
      // Sent or kept as a draft: this list starts again (the other lists keep what was typed).
      // Only this list's products: a line moved here from another list goes, one moved away stays.
      final sentIds = {for (final l in lines) asInt(l['product_id'])};
      setState(() {
        for (final list in _extra.values) {
          list.removeWhere((l) => sentIds.contains(asInt(l['product_id'])));
        }
        _extra.removeWhere((_, list) => list.isEmpty);
        for (final l in lines) {
          _take(asInt(l['product_id']));
          _supplierOf.remove(asInt(l['product_id']));
        }
      });
      _saveCart();
      final before = _drafts;
      await _load(); // what was sent now counts as "on its way"
      if (mounted && _drafts > before) {
        setState(() => _justSaved = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _justSaved = false);
        });
      }
    }
  }

  // ------------------------------------------------------------- remove / budget (v0.48)

  bool _isManual(Map<String, dynamic> l) => '${l['reason']}' == 'manual';

  /// "×", a swipe, or "Ondoa n" on a selection: off the list now; the server
  /// keeps it off for 7 days (unless it runs out completely). "Rudisha" brings it back.
  Future<void> _remove(List<Map<String, dynamic>> lines, {String? label}) async {
    if (lines.isEmpty) return;
    final ids = [for (final l in lines) asInt(l['product_id'])];
    final server = [for (final l in lines) if (!_isManual(l)) asInt(l['product_id'])];
    // Added by hand: just taken out (nothing to remember on the server).
    final manual = <int, List<Map<String, dynamic>>>{};
    final inCart = {for (final id in ids) if (_cart.containsKey(id)) id: (_cart[id]!, _packs[id])};
    setState(() {
      _hidden.addAll(ids);
      for (final id in ids) {
        _take(id);
      }
      for (final e in _extra.entries) {
        final gone = e.value.where((l) => ids.contains(asInt(l['product_id']))).toList();
        if (gone.isNotEmpty) manual[e.key] = gone;
        e.value.removeWhere((l) => ids.contains(asInt(l['product_id'])));
      }
    });
    _saveCart();
    final messenger = ScaffoldMessenger.of(context);
    if (server.isNotEmpty) {
      try {
        await _api.post('reorder/dismiss', {'product_ids': server});
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _hidden.removeAll(server));
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    if (!mounted) return;
    showUndoSnack(messenger, SnackBar(
        content: Text(label ?? (lines.length == 1 ? tr('Imeondolewa: :a', {'a': lines.first['name']}) : tr('Bidhaa :n zimeondolewa', {'n': lines.length}))),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: tr('Rudisha'),
          onPressed: () async {
            if (!mounted) return;
            setState(() {
              _hidden.removeAll(ids);
              for (final e in manual.entries) {
                (_extra[e.key] ??= []).addAll(e.value);
              }
              for (final MapEntry(key: id, value: (entry, packs)) in inCart.entries) {
                _cart[id] = entry;
                if (packs != null) _packs[id] = packs;
              }
            });
            _saveCart();
            if (server.isNotEmpty) {
              try {
                await _api.post('reorder/undismiss', {'product_ids': server});
              } on ApiException catch (e) {
                if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },
        ),
      ));
  }

  /// What one line costs at the last price (scaled when the packaging changed), or null.
  int? _lineCost(Map<String, dynamic> l) {
    if (l['pack_cost'] == null) return null;
    final size = asInt(l['pack_size']) < 1 ? 1 : asInt(l['pack_size']);
    final (_, cur) = _pack(l);
    return (asCost(l['pack_cost']) / size * cur * _chosen(l)).round();
  }

  List<Map<String, dynamic>> get _cartLines => [for (final e in _cart.values) (e['line'] as Map).cast<String, dynamic>()];

  /// Most urgent first: out, runs out, asked for, low; then what sells for the most a day.
  int _rank(Map<String, dynamic> l) => switch ('${l['reason']}') {
        'out' => 0,
        'runs_out' => 1,
        _ when asInt(l['requests']) > 0 => 2,
        'low' => 3,
        'manual' => 4,
        _ => 5,
      };

  /// Keep in the basket, in order of need, what fits in the budget; the rest
  /// steps out (and comes back when the budget is removed).
  void _applyBudget(int? budget) {
    setState(() {
      _cart.addAll(_trimmedOut);
      _trimmedOut.clear();
      _trimmed.clear();
      _budget = budget;
      if (budget == null) return;
      final lines = [..._cartLines]..sort((a, b) {
          final r = _rank(a).compareTo(_rank(b));
          if (r != 0) return r;
          double v(Map<String, dynamic> l) => (l['per_day'] is num ? (l['per_day'] as num).toDouble() : 0.0) * asInt(l['unit_price']);
          return v(b).compareTo(v(a));
        });
      var left = budget;
      for (final l in lines) {
        final c = _lineCost(l) ?? 0; // no last price: kept, it can't be weighed
        if (c <= left) {
          left -= c;
        } else {
          final id = asInt(l['product_id']);
          _trimmed.add(id);
          _trimmedOut[id] = _cart.remove(id)!;
        }
      }
    });
    _saveCart();
  }

  Future<void> _askBudget() async {
    final c = TextEditingController(text: _budget == null ? '' : groupDigits(_budget!));
    final v = await showDialog<int?>(
      context: context,
      builder: (d) => AlertDialog(
        title: const T('Bajeti ya mzigo huu'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const T('Zilizoisha na zinazouzika zaidi zinabaki kwanza; nyingine zinatoka kikapuni.', style: TextStyle(fontSize: 13, color: mutedText)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInput()],
            decoration: InputDecoration(labelText: tr('Kiasi (TSh)')),
          ),
        ]),
        actions: [
          if (_budget != null) TextButton(onPressed: () => Navigator.of(d).pop(-1), child: const T('Ondoa bajeti')),
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(d).pop(moneyValue(c.text)), child: const T('Weka')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    _applyBudget(v <= 0 ? null : v);
  }

  // ------------------------------------------------------------- basket: start, send, buy, save

  /// What's needed now, on the lists shown: out, running out, asked for, low.
  List<(int, Map<String, dynamic>)> get _neededShown => [
        for (final g in _groups)
          for (final l in (g['lines'] as List).cast<Map<String, dynamic>>())
            if (_rank(l) < 4 && !_cart.containsKey(asInt(l['product_id']))) (asInt((g['supplier'] as Map?)?['id']), l),
      ];

  void _takeSuggested() {
    final add = _neededShown;
    if (add.isEmpty) return;
    tick();
    setState(() {
      for (final (k, l) in add) {
        _put(l, k);
      }
      _startMode = 'suggested';
      if (_view != 'needed') _view = 'needed';
    });
    _saveCart();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Bidhaa :n zimewekwa kikapuni. Punguza au toa usizotaka.', {'n': add.length}))));
  }

  Map<String, dynamic> _cartGroup(int key) => {'supplier': _supplierById(key), 'lines': _cartGroups[key] ?? const [], 'lead_days': null};

  /// Tuma: one supplier's order at a time (one WhatsApp message each).
  Future<void> _sendCart() async {
    final groups = _cartGroups;
    if (groups.isEmpty) return;
    if (groups.length == 1) return _send(_cartGroup(groups.keys.first));
    final key = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: T('Kila msambazaji anapata ujumbe wake', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          for (final MapEntry(key: k, value: lines) in groups.entries)
            ListTile(
              leading: const Icon(Icons.send_rounded, color: brandGreen),
              title: Text(_supplierById(k)?['name'] ?? tr('Bila msambazaji'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('bidhaa :n', {'n': lines.length})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(sheet).pop(k),
            ),
        ]),
      ),
    );
    if (key != null && mounted) await _send(_cartGroup(key));
  }

  /// The whole basket becomes the buying trip (Kariakoo, or a rep at the door).
  Future<void> _cartToTrip() async {
    final lines = [
      for (final MapEntry(key: id, value: e) in _cart.entries)
        if (_chosen((e['line'] as Map).cast<String, dynamic>()) > 0)
          {
            'product_id': id,
            'supplier_id': _keyOf(id) == 0 ? null : _keyOf(id),
            'pack_name': _pack((e['line'] as Map).cast<String, dynamic>()).$1,
            'pack_size': _pack((e['line'] as Map).cast<String, dynamic>()).$2,
            'packs': _chosen((e['line'] as Map).cast<String, dynamic>()),
          },
    ];
    if (lines.isEmpty) return;
    try {
      final r = await _api.post('shopping-lists', {'lines': lines}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        for (final l in lines) {
          _take(asInt(l['product_id']));
        }
      });
      _saveCart();
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListScreen(session: widget.session, listId: asInt(r['id']))));
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Hifadhi: the basket as a saved list (a draft; each product keeps its supplier).
  Future<void> _cartToSaved() async {
    final lines = [
      for (final MapEntry(key: id, value: e) in _cart.entries)
        if (_chosen((e['line'] as Map).cast<String, dynamic>()) > 0)
          {
            'product_id': id,
            'supplier_id': _keyOf(id) == 0 ? null : _keyOf(id),
            'pack_name': _pack((e['line'] as Map).cast<String, dynamic>()).$1,
            'pack_size': _pack((e['line'] as Map).cast<String, dynamic>()).$2,
            'packs': _chosen((e['line'] as Map).cast<String, dynamic>()),
            'suggested_packs': (e['line'] as Map)['suggested_packs'],
          },
    ];
    if (lines.isEmpty) return;
    try {
      await _api.post('purchase-orders', {'supplier_id': null, 'cover_days': _cover, 'draft': true, 'lines': lines});
      if (!mounted) return;
      setState(() {
        for (final l in lines) {
          _take(asInt(l['product_id']));
        }
        _justSaved = true;
      });
      _saveCart();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Imehifadhiwa kwenye orodha zilizohifadhiwa (🔖).'))));
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _justSaved = false);
      });
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openLists() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListScreen(session: widget.session)));
    if (mounted) _load();
  }

  /// Kikapu cha agizo: by supplier, amounts, then Hifadhi / Kununua / Tuma.
  Future<void> _openCart() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
        void change(VoidCallback f) {
          setState(f);
          setSheet(() {});
          _saveCart();
        }

        final groups = _cartGroups;
        if (groups.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(sheet).canPop()) Navigator.of(sheet).pop();
          });
        }
        var total = 0;
        var unpriced = 0;
        for (final l in _cartLines) {
          final c = _lineCost(l);
          c == null ? unpriced++ : total += c;
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.86),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                child: Row(children: [
                  const Expanded(child: T('Kikapu cha agizo', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                  TextButton(
                    onPressed: () => change(() {
                      for (final id in [..._cart.keys]) {
                        _take(id);
                      }
                    }),
                    child: const T('Futa vyote', style: TextStyle(color: dangerRed)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  [
                    tr('Bidhaa :n', {'n': _cart.length}),
                    tr('wasambazaji :n', {'n': groups.length}),
                    if (_costs && total > 0) '${unpriced > 0 ? '~' : ''}${formatTsh(total)}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 13, color: mutedText),
                ),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 12, 8), children: [
                  for (final MapEntry(key: k, value: lines) in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 2),
                      child: Row(children: [
                        Expanded(
                          child: Text('${_supplierById(k)?['name'] ?? tr('Bila msambazaji')} · ${lines.length}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedText)),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () async {
                            final to = await _askSupplier(tr('Agiza bidhaa :n kutoka kwa nani?', {'n': lines.length}), k);
                            if (to == null || to == k || !mounted) return;
                            change(() {
                              for (final l in lines) {
                                _supplierOf[asInt(l['product_id'])] = to;
                              }
                            });
                          },
                          child: T(k == 0 ? 'Chagua msambazaji' : 'Badilisha'),
                        ),
                      ]),
                    ),
                    for (final l in lines)
                      Dismissible(
                        key: ValueKey('cart-${l['product_id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: dangerSoft,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const T('Toa', style: TextStyle(color: dangerRed, fontWeight: FontWeight.w800)),
                        ),
                        onDismissed: (_) => change(() => _take(asInt(l['product_id']))),
                        child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEDF2F0)))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                '${unitLabel(_pack(l).$1)}${_pack(l).$2 > 1 ? ' (${_pack(l).$2})' : ''}'
                                '${_costs && _lineCost(l) != null ? ' · ${groupDigits(_lineCost(l)!)}' : ''}',
                                style: const TextStyle(fontSize: 12, color: mutedText),
                              ),
                            ]),
                          ),
                          _stepper(_chosen(l), (v) => change(() => v == 0 ? _take(asInt(l['product_id'])) : _packs[asInt(l['product_id'])] = v)),
                          const SizedBox(width: 6),
                          // Out of the basket in one tap (it stays on the list, as + Weka).
                          Pressable(
                            onTap: () => change(() => _take(asInt(l['product_id']))),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(color: dangerSoft, shape: BoxShape.circle),
                              child: Icon(Icons.close_rounded, size: 16, color: dangerRed.withValues(alpha: 0.85), semanticLabel: tr('Toa kikapuni')),
                            ),
                          ),
                        ]),
                      ),
                      ),
                  ],
                ]),
              ),
              // Hifadhi and Kununua side by side, Tuma full width under them (v0.48.2: "Sav" was cut off).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  for (final (key, icon, label) in [
                    ('save', Icons.bookmark_outline_rounded, 'Hifadhi kwa baadaye'),
                    ('trip', Icons.shopping_bag_outlined, 'Orodha ya kununua'),
                  ]) ...[
                    if (key == 'trip') const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(sheet).pop(key),
                        icon: Icon(icon, size: 18),
                        label: FittedBox(fit: BoxFit.scaleDown, child: T(label, maxLines: 1)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheet).pop('send'),
                  icon: const Icon(Icons.send_rounded, size: 19),
                  label: Text(groups.length > 1 ? tr('Tuma kwa wasambazaji :n', {'n': groups.length}) : tr('Tuma kwa WhatsApp'), maxLines: 1),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (!mounted) return;
    switch (action) {
      case 'save':
        await _cartToSaved();
      case 'trip':
        await _cartToTrip();
      case 'send':
        await _sendCart();
    }
  }

  // ------------------------------------------------------------- hold to select

  void _startPicking(int id) {
    tick();
    setState(() {
      _picking = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _stopPicking() => setState(() {
        _picking = false;
        _selected.clear();
      });

  List<(int, Map<String, dynamic>)> get _selectedLines => [
        for (final g in _groups)
          for (final l in (g['lines'] as List).cast<Map<String, dynamic>>())
            if (_selected.contains(asInt(l['product_id']))) (asInt((g['supplier'] as Map?)?['id']), l),
      ];

  Future<void> _pickedAction(String what) async {
    final picked = _selectedLines;
    if (picked.isEmpty) return;
    if (what == 'remove') {
      _stopPicking();
      return _remove([for (final (_, l) in picked) l]);
    }
    if (what == 'supplier') {
      final to = await _askSupplier(tr('Agiza bidhaa :n kutoka kwa nani?', {'n': picked.length}), picked.first.$1);
      if (to == null || !mounted) return;
      setState(() {
        for (final (_, l) in picked) {
          _supplierOf[asInt(l['product_id'])] = to;
        }
      });
      _saveCart();
      _stopPicking();
      return;
    }
    setState(() {
      for (final (k, l) in picked) {
        _put(l, k);
      }
    });
    _saveCart();
    _stopPicking();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Bidhaa :n zimewekwa kikapuni.', {'n': picked.length}))));
  }

  // ------------------------------------------------------------- Imefika, Wanaouliza

  /// It came in: call or text the customers who asked, then "Nimewajulisha".
  Future<void> _arrivedSheet(Map<String, dynamic> a) async {
    final customers = ((a['customers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final shop = widget.session.user?.shopName ?? '';
    final told = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(':a imefika', {'a': a['name']}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(tr('Wateja :n waliuliza. Wajulishe warudi.', {'n': a['count']}), style: const TextStyle(color: mutedText)),
            const SizedBox(height: 8),
            if (customers.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: T('Hawakuacha namba za simu.', style: TextStyle(color: mutedText))),
            for (final c in customers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: primarySoft, child: Icon(Icons.person_outline, color: brandGreen)),
                title: Text('${c['name'] ?? tr('Mteja')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${c['phone']}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr('Piga simu'),
                    icon: const Icon(Icons.call_outlined, color: brandGreen),
                    onPressed: () => launchUrl(Uri.parse('tel:${'${c['phone']}'.replaceAll(' ', '')}')),
                  ),
                  IconButton(
                    tooltip: 'WhatsApp',
                    icon: const Icon(Icons.chat_outlined, color: brandGreen),
                    onPressed: () {
                      var digits = '${c['phone']}'.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.startsWith('0')) digits = '255${digits.substring(1)}';
                      final text = tr('Habari, :a uliyoulizia imefika :shop. Karibu.', {'a': a['name'], 'shop': shop});
                      launchUrl(Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
                    },
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(sheet).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const T('Nimewajulisha'),
            ),
          ]),
        ),
      ),
    );
    if (told != true || !mounted) return;
    try {
      await _api.post('product-requests/notified', {'ids': a['ids']});
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Asked for, not in the shop at all: add it (then order), or let it go.
  Future<void> _unknownAction(Map<String, dynamic> u, String action) async {
    if (action == 'close') {
      try {
        await _api.post('product-requests/close', {'ids': u['ids']});
        if (mounted) _load();
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!_canCreate) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Mwombe mwenye ruhusa ya kuongeza bidhaa.'))));
      return;
    }
    final made = await _createProduct('${u['name']}');
    if (made == null || !mounted) return;
    final line = <String, dynamic>{
      'product_id': made.id,
      'name': made.name,
      'units': [for (final x in made.units) {'name': x.name, 'base_quantity': x.baseQuantity, 'price': x.price}],
      'on_hand': 0,
      'days_left': null,
      'on_order': 0,
      'reason': 'manual',
      'requests': u['count'],
      'pack_name': made.units.isEmpty ? made.baseUnit : made.units.last.name,
      'pack_size': made.units.isEmpty ? 1 : made.units.last.baseQuantity,
      'pack_cost': null,
      'suggested_packs': null,
    };
    setState(() {
      (_extra[0] ??= []).add(line);
      _put(line, 0);
    });
    _saveCart();
  }

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    var total = 0;
    var unpriced = 0;
    for (final l in _cartLines) {
      final c = _lineCost(l);
      c == null ? unpriced++ : total += c;
    }
    final arrived = ((_data?['arrived'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final unknown = ((_data?['unknown_requests'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final needed = _neededShown.length;
    final shownIds = [for (final g in groups) for (final l in (g['lines'] as List).cast<Map<String, dynamic>>()) asInt(l['product_id'])];

    return PopScope(
      canPop: !_draftChanged && !_picking,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_picking) return _stopPicking();
        _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: _picking
            ? AppBar(
                backgroundColor: Colors.white,
                leading: IconButton(tooltip: tr('Ghairi'), icon: const Icon(Icons.close_rounded), onPressed: _stopPicking),
                title: Text(tr(':n zimechaguliwa', {'n': _selected.length}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _selected.length == shownIds.length ? _selected.clear() : _selected.addAll(shownIds)),
                    child: T(_selected.length == shownIds.length ? 'Ondoa alama zote' : 'Chagua zote'),
                  ),
                ],
              )
            : AppBar(
                backgroundColor: pageBackground,
                title: const T('Agiza', style: TextStyle(fontWeight: FontWeight.w800)),
                actions: [
                  if (_drafts > 0 || _draft != null)
                    IconButton(
                      tooltip: tr('Zilizohifadhiwa'),
                      onPressed: _showDrafts,
                      icon: Badge(
                        label: Text('$_drafts'),
                        isLabelVisible: _drafts > 0,
                        backgroundColor: _justSaved ? brandGreen : infoBlue,
                        child: const Icon(Icons.bookmark_outline_rounded),
                      ),
                    ),
                  if (_lists > 0)
                    IconButton(
                      tooltip: tr('Orodha ya kununua'),
                      onPressed: _openLists,
                      icon: Badge(label: Text('$_lists'), child: const Icon(Icons.shopping_bag_outlined)),
                    ),
                  TextButton(onPressed: () => _openOrders('all'), child: const T('Maagizo')),
                ],
              ),
        bottomNavigationBar: _picking ? _pickBar() : (_cart.isEmpty ? null : _basketPill(total, unpriced)),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _summary(total, unpriced),
              if (!_picking && (_mode != null || (_cart.isEmpty && needed > 0)))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AnimatedSize(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.curve,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.base),
                      switchInCurve: Motion.curve,
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(0, .12), end: Offset.zero).animate(a), child: c),
                      ),
                      child: _mode == null ? KeyedSubtree(key: const ValueKey('cards'), child: _startCards(needed)) : _modeStrip(needed),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _tabs(),
              if (_view == 'all')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    controller: _filter,
                    focusNode: _filterFocus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tafuta bidhaa…'), isDense: true),
                  ),
                ),
              for (final a in arrived) _arrivedCard(a),
              if (_open.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Pressable(
                    onTap: () => _openOrders('sent'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Icon(Icons.local_shipping_outlined, color: brandGreen, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(tr('Maagizo :open yanasubiri kufika', {'open': _open.length}),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        ),
                        const Icon(Icons.chevron_right, color: mutedText),
                      ]),
                    ),
                  ),
                ),
              if (_view == 'requests' && unknown.isNotEmpty) _unknownCard(unknown),
              if (_loading && _data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: AfyaLoader())),
              if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: dangerRed))),
              if (!_loading && _error == null && groups.isEmpty && _draft == null && !(_view == 'requests' && unknown.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: T(
                    _view == 'requests'
                        ? 'Hakuna aliyeulizia bidhaa isiyokuwepo. Kwenye Uza, bidhaa ikikosekana gusa "Mteja ameulizia".'
                        : 'Hakuna kinachohitajika sasa. Angalia "Zote" kuagiza bidhaa yoyote.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: mutedText),
                  ),
                ),
              if (_draft != null) _draftCard(),
              for (final g in groups) _group(g),
              const SizedBox(height: 12),
              if (!_picking)
                TextButton.icon(
                  onPressed: _data == null ? null : _orderAnything,
                  icon: const Icon(Icons.add),
                  label: const T('Agiza bidhaa nyingine yoyote'),
                ),
              if (!_picking && groups.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: T('Shikilia bidhaa kuchagua kadhaa kwa pamoja.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: mutedText)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty basket: take every suggestion in one tap, or pick one by one.
  Widget _startCards(int needed) => Row(children: [
        Expanded(
          child: Pressable(
            onTap: _takeSuggested,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const T('Anza na pendekezo', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tr('Weka zote :n kikapuni', {'n': needed}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Pressable(
            // v0.48.2: it did nothing. Now the cards step aside and the + Weka buttons are the way.
            onTap: () {
              // v0.48.3: picking your own means from everything: open Zote, search ready.
              tick();
              setState(() {
                _startMode = 'own';
                _view = 'all';
                _filter.clear();
              });
              _load();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _filterFocus.requestFocus();
              });
            },
            child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              T('Chagua mwenyewe', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              T('Moja moja kwa + Weka', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mutedText, fontSize: 12)),
            ]),
          ),
          ),
        ),
      ]);

  /// After a start card: a strip that says which way the basket is being built,
  /// with the way to switch (instead of the cards just disappearing).
  Widget _modeStrip(int needed) {
    final suggested = _mode == 'suggested';
    return Container(
      key: ValueKey('strip$_mode'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: suggested ? const Color(0xFFE3F4EC) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: suggested ? const Color(0xFFBFE3D2) : const Color(0xFFDCE5E1)),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: suggested ? brandGreen : const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(11)),
          child: Icon(suggested ? Icons.auto_awesome_rounded : Icons.touch_app_outlined, size: 18, color: suggested ? Colors.white : const Color(0xFF0E3B31)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(suggested ? tr('Pendekezo liko kikapuni') : tr('Unachagua mwenyewe'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text(suggested ? tr('Punguza, ongeza au toa usizotaka.') : tr('Tafuta, kisha gusa + Weka.'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
          ]),
        ),
        TextButton(
          onPressed: () {
            tick();
            if (suggested) {
              // Start again: what the suggestion put in comes out (with Rudisha).
              final before = {for (final e in _cart.entries) e.key: (e.value, _packs[e.key])};
              setState(() {
                for (final id in [..._cart.keys]) {
                  _take(id);
                }
                _startMode = null;
              });
              _saveCart();
              showUndoSnack(
                ScaffoldMessenger.of(context),
                SnackBar(
                  content: Text(tr('Kikapu kimeondolewa')),
                  action: SnackBarAction(
                    label: tr('Rudisha'),
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        for (final MapEntry(key: id, value: (e, p)) in before.entries) {
                          _cart[id] = e;
                          if (p != null) _packs[id] = p;
                        }
                        _startMode = 'suggested';
                      });
                      _saveCart();
                    },
                  ),
                ),
              );
            } else if (needed > 0) {
              _takeSuggested();
            } else {
              setState(() => _startMode = null);
            }
          },
          child: Text(suggested ? tr('Anza upya') : (needed > 0 ? tr('Tumia pendekezo') : tr('Funga'))),
        ),
      ]),
    );
  }

  /// The basket, like the till's: count, total, and the way into it.
  Widget _basketPill(int total, int unpriced) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Pressable(
            onTap: _openCart,
            child: Container(
              height: 58,
              padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
              decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(99)),
              child: Row(children: [
                const Icon(Icons.shopping_basket_outlined, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${tr('Kikapu · :n', {'n': _cart.length})}${_costs && total > 0 ? ' · ${unpriced > 0 ? '~' : ''}${formatTsh(total)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFF3DDC97), borderRadius: BorderRadius.circular(99)),
                  child: const T('Endelea', style: TextStyle(color: Color(0xFF0E3B31), fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _roundAction(IconData icon, String label, Color fg, Color bg, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(
            width: 70,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, color: fg, size: 20)),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      );

  /// Selecting: one action for every ticked product.
  Widget _pickBar() {
    final n = _selected.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3EDE8)))),
        child: Row(children: [
          // Small round actions with their word under them: they never squeeze to "Re…".
          _roundAction(Icons.remove_circle_outline_rounded, tr('Ondoa'), dangerRed, dangerSoft, n == 0 ? null : () => _pickedAction('remove')),
          const SizedBox(width: 6),
          _roundAction(Icons.local_shipping_outlined, tr('Msambazaji'), const Color(0xFF0E3B31), const Color(0xFFEFF4F2), n == 0 ? null : () => _pickedAction('supplier')),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: n == 0 ? null : () => _pickedAction('cart'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), padding: const EdgeInsets.symmetric(horizontal: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(tr('Weka kikapuni :n', {'n': n}), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
      ),
    );
  }

  /// "Kikapu: bidhaa 7 · TSh 9,282", how far ahead, and the budget.
  Widget _summary(int total, int unpriced) {
    final n = _cart.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n == 0 ? tr('Kikapu ni tupu') : tr('Kikapuni: bidhaa :n', {'n': n}), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _costs ? (total == 0 && n > 0 ? '—' : '${unpriced > 0 ? '~' : ''}${formatTsh(total)}') : tr('Bidhaa :n', {'n': n}),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              if (_costs && unpriced > 0)
                Text(tr(':n bila bei ya mwisho', {'n': unpriced}), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            ]),
          ),
          PopupMenuButton<int>(
            tooltip: tr('Agiza kiasi cha kutosha kwa:'),
            initialValue: _cover,
            onSelected: (v) {
              setState(() => _cover = v);
              _load(fresh: true);
            },
            itemBuilder: (_) => [for (final (d, label) in _covers) PopupMenuItem(value: d, child: Text(tr('Kwa :a', {'a': tr(label)})))],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Kwa :a', {'a': tr(_covers.firstWhere((c) => c.$1 == _cover).$2)}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
              ]),
            ),
          ),
        ]),
        if (_costs) ...[
          const SizedBox(height: 10),
          Pressable(
            onTap: _askBudget,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _budget == null ? Colors.white10 : const Color(0xFF3DDC97).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_outlined, size: 18, color: _budget == null ? Colors.white70 : const Color(0xFF3DDC97)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _budget == null
                        ? tr('Weka bajeti')
                        : '${tr('Bajeti :a', {'a': formatTsh(_budget!)})}${_trimmed.isEmpty ? '' : ' · ${tr(':n zimetoka kikapuni', {'n': _trimmed.length})}'}',
                    style: TextStyle(color: _budget == null ? Colors.white70 : Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(_budget == null ? Icons.add_rounded : Icons.edit_outlined, size: 16, color: Colors.white54),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        for (final (v, label) in _views)
          Expanded(
            child: Pressable(
              onTap: () {
                if (_view == v) return;
                setState(() {
                  _view = v;
                  _filter.clear();
                  _selected.clear();
                });
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: _view == v ? inkColor : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: Text(tr(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _view == v ? Colors.white : inkColor)),
                  ),
                  if (v != 'all' && asInt(_counts[v]) > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _view == v ? Colors.white24 : (v == 'requests' ? infoSoft : primarySoft),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('${_counts[v]}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _view == v ? Colors.white : (v == 'requests' ? infoBlue : brandGreen))),
                    ),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _arrivedCard(Map<String, dynamic> a) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Pressable(
          onTap: () => _arrivedSheet(a),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.campaign_outlined, color: brandGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Imefika: :a', {'a': a['name']}), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(tr('Wateja :n waliuliza · wajulishe', {'n': a['count']}), style: const TextStyle(fontSize: 12.5, color: mutedText)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: brandGreen),
            ]),
          ),
        ),
      );

  /// Asked for, but not a product of this shop (typed at the till).
  Widget _unknownCard(List<Map<String, dynamic>> unknown) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const T('Hazipo dukani kabisa', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const T('Wateja waliuliza; ziongeze kuziagiza, au ziache.', style: TextStyle(fontSize: 12.5, color: mutedText)),
          const SizedBox(height: 4),
          for (final u in unknown)
            Row(children: [
              Expanded(
                child: Text('${u['name']}', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              _badge(tr('wateja :n', {'n': u['count']}), infoSoft, infoBlue),
              PopupMenuButton<String>(
                onSelected: (v) => _unknownAction(u, v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'add', child: T('Ongeza bidhaa hii, iagize')),
                  PopupMenuItem(value: 'close', child: T('Ondoa kwenye orodha')),
                ],
              ),
            ]),
        ]),
      );

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      );

  /// One supplier: name, how many, what's in the basket from it; tap to fold. ⋮ for the rest.
  Widget _group(Map<String, dynamic> g) {
    final s = g['supplier'] as Map<String, dynamic>?;
    final key = asInt(s?['id']);
    final lines = ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final lead = g['lead_days'];
    final inCart = lines.where((l) => _cart.containsKey(asInt(l['product_id']))).length;
    var total = 0;
    for (final l in lines) {
      total += _lineCost(l) ?? 0;
    }
    final folded = _folded.contains(key);
    final note = [
      tr('bidhaa :n', {'n': lines.length}),
      if (inCart > 0) tr(':n kikapuni', {'n': inCart}),
      if (lead != null && inCart == 0) tr('huleta ~siku :lead', {'lead': lead}),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => folded ? _folded.remove(key) : _folded.add(key)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 2, 10),
            child: Row(children: [
              AnimatedRotation(
                turns: folded ? -0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more_rounded, color: mutedText),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s == null ? tr('Bila msambazaji') : '${s['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
                ]),
              ),
              if (_costs && total > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(groupDigits(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                ),
              PopupMenuButton<String>(
                tooltip: tr('Orodha hii'),
                onSelected: (v) {
                  if (v == 'remove') {
                    _remove(lines, label: tr('Bidhaa :n za :a zimeondolewa', {'n': lines.length, 'a': s?['name'] ?? tr('bila msambazaji')}));
                  } else if (v == 'pick') {
                    setState(() {
                      _picking = true;
                      _selected
                        ..clear()
                        ..addAll(lines.map((l) => asInt(l['product_id'])));
                    });
                  } else {
                    _groupAction(v, lines, key);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'all', child: T('Weka zote kikapuni')),
                  if (inCart > 0) PopupMenuItem(value: 'none', child: T('Toa zote kikapuni')),
                  PopupMenuItem(value: 'pick', child: T('Chagua kadhaa')),
                  PopupMenuItem(value: 'supplier', child: T('Agiza zote kutoka kwa…')),
                  if (_draft != null) PopupMenuItem(value: 'todraft', child: T('Weka zilizochaguliwa kwenye rasimu')),
                  PopupMenuItem(value: 'remove', child: T('Ondoa zote', style: TextStyle(color: dangerRed))),
                ],
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: folded
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final l in lines) _line(l, key),
                  if (!_picking)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addProduct(key),
                        icon: const Icon(Icons.add, size: 18),
                        label: const T('Ongeza bidhaa'),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }

  /// The draft being continued, split by supplier: each part has its own
  /// "Tuma kwa …" (one order, one message); the other parts stay for later.
  Widget _draftCard() {
    final s = _supplierById(_draftSupplier);
    final chosen = _draftLines.where((l) => _chosen(l) > 0).length;
    final keys = <int>[];
    for (final l in _draftLines) {
      final k = asInt(l['supplier_id']);
      if (!keys.contains(k)) keys.add(k);
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: infoBlue.withValues(alpha: 0.45))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const T('Orodha iliyohifadhiwa', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: infoBlue)),
                Text(tr('Bidhaa :n · tuma kila msambazaji akiwa tayari', {'n': chosen}), style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') return _deleteDraft();
                final k = await _askSupplier(tr('Bidhaa zote za rasimu kutoka kwa nani?'), _draftSupplier);
                if (k == null || !mounted) return;
                setState(() {
                  _draftSupplier = k;
                  for (final l in _draftLines) {
                    l['supplier_id'] = k;
                  }
                });
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'supplier', child: Text(tr('Zote: :a', {'a': s?['name'] ?? tr('chagua')}))),
                PopupMenuItem(value: 'delete', child: T('Futa rasimu', style: TextStyle(color: dangerRed))),
              ],
            ),
          ]),
        ),
        for (final k in keys) ...[
          Container(
            color: infoSoft,
            padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${_supplierById(k)?['name'] ?? tr('Bila msambazaji bado')} · ${tr('bidhaa :n', {'n': _draftLines.where((l) => asInt(l['supplier_id']) == k).length})}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: _savingDraft || !_draftLines.any((l) => asInt(l['supplier_id']) == k && _chosen(l) > 0) ? null : () => _sendDraftPart(k),
                child: const T('Tuma'),
              ),
            ]),
          ),
          for (final l in _draftLines.where((l) => asInt(l['supplier_id']) == k)) _line(l, k, inDraft: true),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 10),
          child: Row(children: [
            TextButton.icon(
              onPressed: () => _addProduct(_draftSupplier, toDraft: true),
              icon: const Icon(Icons.add, size: 18),
              label: const T('Ongeza bidhaa'),
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: _savingDraft ? null : _saveDraft,
              child: T(_draftChanged ? 'Hifadhi mabadiliko' : 'Imehifadhiwa'),
            ),
          ]),
        ),
      ]),
    );
  }

  /// One compact row: name and why, the packaging; then "+ Weka · n" (not in the
  /// basket yet) or − n + (in it), and a × in a pale red circle. Hold to select.
  Widget _line(Map<String, dynamic> l, int supplierKey, {bool inDraft = false}) {
    final id = asInt(l['product_id']);
    final onHand = asInt(l['on_hand']);
    final days = l['days_left'];
    final units = _units(l);
    final reason = '${l['reason']}';
    final requests = asInt(l['requests']);
    final (packName, packSize) = _pack(l);
    final (why, bg, fg) = switch (reason) {
      'out' => (tr('Imeisha'), dangerSoft, dangerRed),
      'runs_out' => (tr('Siku :days', {'days': days}), warnSoft, warnAmber),
      'low' => (tr('Chini'), warnSoft, warnAmber),
      'asked' => (tr('Wanaouliza'), infoSoft, infoBlue),
      'draft' => (tr('Rasimu'), infoSoft, infoBlue),
      'manual' => (tr('Umeongeza'), const Color(0xFFEFF3F1), mutedText),
      _ => (tr('Inatosha'), const Color(0xFFEFF3F1), mutedText),
    };
    final inCart = inDraft || _cart.containsKey(id);
    final n = _chosen(l);
    final cost = _lineCost(l);
    final picking = _picking && !inDraft;
    final selected = _selected.contains(id);

    Widget trailing;
    if (picking) {
      trailing = Padding(
        padding: const EdgeInsets.only(right: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: selected ? brandGreen : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? brandGreen : const Color(0xFFB7C6C0), width: 1.6),
          ),
          child: selected ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
        ),
      );
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        // The two states swap with a short cross-fade and resize, not a jump.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(a), child: child)),
          child: inCart
              ? KeyedSubtree(
                  key: const ValueKey('in'),
                  child: _stepper(n, (v) {
                    setState(() {
                      if (v == 0 && !inDraft) {
                        _take(id);
                      } else {
                        _packs[id] = v;
                        _trimmed.remove(id);
                      }
                    });
                    _saveCart();
                  }),
                )
              : KeyedSubtree(key: const ValueKey('out'), child: _addButton(l, supplierKey)),
        ),
        const SizedBox(width: 8),
        // A small pale-red circle: clearly a button, not loud.
        Pressable(
          onTap: () => inDraft ? _removeFromDraft(l) : _remove([l]),
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(color: dangerSoft, shape: BoxShape.circle),
            child: Icon(Icons.close_rounded, size: 16, color: dangerRed.withValues(alpha: 0.85), semanticLabel: tr('Ondoa')),
          ),
        ),
        const SizedBox(width: 10),
      ]);
    }

    final row = Material(
      color: picking && selected ? const Color(0xFFF2FAF6) : Colors.white,
      child: InkWell(
        onLongPress: inDraft || _picking ? null : () => _startPicking(id),
        onTap: picking ? () => setState(() => selected ? _selected.remove(id) : _selected.add(id)) : null,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEDF2F0)))),
          padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: inkColor)),
                const SizedBox(height: 3),
                Wrap(spacing: 5, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _badge(why, bg, fg),
                  if (requests > 0 && reason != 'asked') _badge(tr('wateja :n', {'n': requests}), infoSoft, infoBlue),
                  if (_trimmed.contains(id)) _badge(tr('bajeti'), const Color(0xFFEFF3F1), mutedText),
                  // v0.48.3: the line's cost lives here, so the stepper and × stay on one line.
                  if (inCart && _costs && cost != null && n > 0)
                    Text('· ${groupDigits(cost)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: inkColor)),
                  // The packaging is a button: strips last time, boxes now.
                  InkWell(
                    onTap: picking ? null : () => _choosePack(l),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      child: Text(
                        '${unitLabel(packName)}${packSize > 1 ? ' ($packSize)' : ''} · ${tr('zipo :a', {'a': describeStock(onHand, units)})}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: brandGreen, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (inDraft || _supplierOf.containsKey(id))
                    InkWell(
                      onTap: () async {
                        if (!inDraft) return _moveLine(l, supplierKey);
                        final k = await _askSupplier(tr('Agiza :a kutoka kwa nani?', {'a': l['name']}), supplierKey);
                        if (k != null && mounted) setState(() => l['supplier_id'] = k);
                      },
                      child: Text(tr('Kutoka: :a', {'a': _supplierById(supplierKey)?['name'] ?? tr('bila msambazaji')}),
                          style: const TextStyle(fontSize: 11.5, color: mutedText, decoration: TextDecoration.underline)),
                    ),
                ]),
              ]),
            ),
            const SizedBox(width: 6),
            trailing,
          ]),
        ),
      ),
    );

    if (_picking) return row;
    return Dismissible(
      key: ValueKey('line-$id-$inDraft'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: dangerSoft,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const T('Ondoa', style: TextStyle(color: dangerRed, fontWeight: FontWeight.w800)),
      ),
      onDismissed: (_) => inDraft ? _removeFromDraft(l) : _remove([l]),
      child: row,
    );
  }

  Widget _addButton(Map<String, dynamic> l, int supplierKey) =>
          Pressable(
            onTap: () {
              tick();
              setState(() => _put(l, supplierKey));
              _saveCart();
            },
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, size: 17, color: primaryStrong),
                const SizedBox(width: 3),
                Text(tr('Weka · :n', {'n': _suggest(l)}), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: primaryStrong)),
              ]),
            ),
          );

  void _removeFromDraft(Map<String, dynamic> l) {
    final i = _draftLines.indexOf(l);
    if (i < 0) return;
    final packs = _packs[asInt(l['product_id'])];
    setState(() => _draftLines.removeAt(i));
    showUndoSnack(ScaffoldMessenger.of(context), SnackBar(
        content: Text(tr('Imeondolewa kwenye rasimu: :a. Kumbuka kuihifadhi.', {'a': l['name']})),
        action: SnackBarAction(
          label: tr('Rudisha'),
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _draftLines.insert(i.clamp(0, _draftLines.length), l);
              if (packs != null) _packs[asInt(l['product_id'])] = packs;
            });
          },
        ),
      ));
  }

  /// − n +, small: the number is what's ordered, in the packaging shown.
  Widget _stepper(int n, ValueChanged<int> set) {
    Widget b(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap == null ? null : () {
            tick();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: onTap == null ? const Color(0xFFC5D2CD) : brandGreen)),
        );
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        b(Icons.remove_rounded, n > 0 ? () => set(n - 1) : null),
        // Tap the number to type it: 24 boxes without 24 taps (v0.48.2).
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final v = await askText(context, title: tr('Idadi'), label: tr('Idadi'), initial: '$n', digitsOnly: true, required: true);
            final k = int.tryParse(v ?? '');
            if (k != null && k >= 0 && k <= 100000) set(k);
          },
          child: SizedBox(
            width: 36,
            height: 32,
            child: Center(child: Text('$n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n == 0 ? mutedText : inkColor, decoration: TextDecoration.underline, decorationColor: const Color(0xFFC5D2CD)))),
          ),
        ),
        b(Icons.add_rounded, () => set(n + 1)),
      ]),
    );
  }
}

/// Pick what to order (v0.46.1): the shop's whole list, A–Z, to scroll
/// through, so nothing is forgotten; or type to narrow it. Tap several, then
/// "Ongeza". The ones that are out or low come first under "Zinaisha", since
/// those are what people forget. Pops a `List<Product>`, or the typed name (a
/// String) for a product the shop doesn't have yet.
class _ProductPickSheet extends StatefulWidget {
  const _ProductPickSheet({required this.api, this.canCreate = false});

  final ApiClient api;

  /// May add a product the shop doesn't have yet (pops the typed name, a String).
  final bool canCreate;

  @override
  State<_ProductPickSheet> createState() => _ProductPickSheetState();
}

class _ProductPickSheetState extends State<_ProductPickSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Product> _all = []; // the whole list, loaded once
  List<Product>? _found; // the server's answer for a typed search (names it knows differently)
  final _picked = <int, Product>{};
  bool _loading = true;
  bool _lowOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.get('products', query: {'all': '1'}) as List;
      if (mounted) setState(() => _all = d.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException {
      // an empty list says so below
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Typing filters the list at once; the server is asked too, for brand,
  /// ingredient and barcode matches the name alone misses.
  void _search(String q) {
    setState(() => _found = null);
    _debounce?.cancel();
    if (q.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final d = await widget.api.get('products', query: {'q': q.trim()}) as List;
        if (mounted && q == _q.text) setState(() => _found = d.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList());
      } on ApiException {
        // the local filter stays
      }
    });
  }

  bool _low(Product p) => p.onHand <= 0 || p.lowStock;

  List<Product> get _shown {
    final q = _q.text.trim().toLowerCase();
    var list = q.isEmpty ? _all : _all.where((p) => p.name.toLowerCase().contains(q)).toList();
    if (q.isNotEmpty && _found != null) {
      final ids = list.map((p) => p.id).toSet();
      list = [...list, ..._found!.where((p) => !ids.contains(p.id))];
    }
    if (_lowOnly) list = list.where(_low).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final typed = _q.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const T('Agiza bidhaa gani?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _q,
            onChanged: (q) {
              setState(() {});
              _search(q);
            },
            decoration: InputDecoration(
              hintText: tr('Andika jina, au pitia orodha'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: typed.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _q.clear())),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilterChip(
              label: Text(tr('Zinaisha tu')),
              avatar: const Icon(Icons.warning_amber_rounded, size: 16),
              selected: _lowOnly,
              onSelected: (v) => setState(() => _lowOnly = v),
            ),
            const Spacer(),
            Text(tr('bidhaa :n', {'n': '${shown.length}'}), style: const TextStyle(fontSize: 12, color: mutedText)),
          ]),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.inventory_2_outlined, size: 44, color: mutedText),
                          const SizedBox(height: 8),
                          Text(_all.isEmpty ? tr('Duka hili halina bidhaa bado.') : tr('Hakuna inayolingana na ":q".', {'q': typed}),
                              textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
                        ]),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final p = shown[i];
                          final on = _picked.containsKey(p.id);
                          final letter = p.name.isEmpty ? '' : p.name[0].toUpperCase();
                          final head = typed.isEmpty && (i == 0 || (shown[i - 1].name.isEmpty ? '' : shown[i - 1].name[0].toUpperCase()) != letter);
                          final low = _low(p);
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (head)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 10, 0, 2),
                                child: Text(letter, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
                              ),
                            Material(
                              color: on ? const Color(0xFFE6F4EC) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                leading: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.onHand <= 0 ? dangerRed : (low ? warnAmber : brandGreen)),
                                ),
                                minLeadingWidth: 10,
                                title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(p.onHand <= 0 ? tr('Imeisha') : tr('Zipo: :a', {'a': describeStock(p.onHand, p.units)}),
                                    style: TextStyle(fontSize: 12, color: p.onHand <= 0 ? dangerRed : mutedText)),
                                trailing: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(on ? Icons.check_circle_rounded : Icons.add_circle_outline,
                                      key: ValueKey(on), color: brandGreen),
                                ),
                                onTap: () => setState(() => on ? _picked.remove(p.id) : _picked[p.id] = p),
                              ),
                            ),
                          ]);
                        },
                      ),
          ),
          const SizedBox(height: 8),
          if (_picked.isNotEmpty)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_picked.values.toList()),
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: Text(tr('Ongeza :n kwenye oda', {'n': '${_picked.length}'})),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            )
          else if (widget.canCreate)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(typed),
              icon: const Icon(Icons.add_box_outlined),
              label: Text(typed.length >= 2 ? tr('Bidhaa mpya: :a', {'a': typed}) : tr('Bidhaa mpya (haipo dukani)')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            )
          else
            const T('Bidhaa ambayo haipo kabisa kwenye duka: iongeze kupitia Pokea mzigo ikifika.',
                style: TextStyle(fontSize: 12, color: mutedText)),
        ]),
      ),
    );
  }
}
