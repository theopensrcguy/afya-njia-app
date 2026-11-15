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
import '../../core/units.dart';
import '../../models/product.dart';
import '../purchases/new_product.dart';
import '../purchases/new_product_screen.dart';
import 'order_send_screen.dart';
import 'orders_screen.dart';
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
  static const _views = [('suggested', 'Pendekezo'), ('alerts', 'Tahadhari'), ('all', 'Zote')];

  int _cover = 14;
  String _view = 'suggested';
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
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
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
      if (widget.draftId != null && _draft == null) await _loadDraft();
      final d = await _api.get('reorder', query: {'cover': '$_cover', 'view': _view}) as Map<String, dynamic>;
      final open = (await _api.get('purchase-orders') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _data = d;
        _open = open;
        if (fresh) {
          _packs.removeWhere((id, _) => !_isExtra(id));
          _packOf.removeWhere((id, _) => !_isExtra(id));
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The draft's products become lines like any other (same amount/packaging controls).
  Future<void> _loadDraft() async {
    final o = await _api.get('purchase-orders/${widget.draftId}') as Map<String, dynamic>;
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
    bool shown(Map<String, dynamic> l) => q.isEmpty || '${l['name']}'.toLowerCase().contains(q);
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
        final id = asInt(l['product_id']);
        // "Chagua zote" keeps what is already set (a suggestion, or a typed amount) and puts 1 on the rest.
        _packs[id] = action == 'none' ? 0 : (_chosen(l) > 0 ? _chosen(l) : 1);
      }
    });
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

  int _chosen(Map<String, dynamic> l) => _packs[asInt(l['product_id'])] ?? asInt(l['suggested_packs']);

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
    final p = picked is String ? await _createProduct(picked) : picked as Product;
    if (p == null || !mounted) return;
    final already = _inDraft(p.id) ||
        (!toDraft && _groups.expand((g) => (g['lines'] as List).cast<Map<String, dynamic>>()).any((l) => asInt(l['product_id']) == p.id));
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(':name tayari iko kwenye orodha.', {'name': p.name}))));
      return;
    }
    final biggest = p.units.isEmpty ? null : p.units.last;
    setState(() {
      (toDraft ? _draftLines : (_extra[supplierKey] ??= [])).add({
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
      });
      _packs[p.id] = 1;
    });
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
                  const SizedBox(width: 8),
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
          _packs.remove(asInt(l['product_id']));
          _packOf.remove(asInt(l['product_id']));
          _supplierOf.remove(asInt(l['product_id']));
        }
      });
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

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return PopScope(
      canPop: !_draftChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      // Drafts wait in the corner: saving one leaves this screen as it is
      // (start the next order straight away); open one only when you choose.
      floatingActionButton: _drafts == 0 && _draft == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showDrafts,
              backgroundColor: _justSaved ? brandGreen : const Color(0xFF2F5FA8),
              foregroundColor: Colors.white,
              icon: Icon(_justSaved ? Icons.check_circle : Icons.edit_note),
              label: Text(_justSaved ? tr('Rasimu imehifadhiwa ✓') : tr('Rasimu :n', {'n': _drafts})),
            ),
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          T('Agiza', style: TextStyle(fontWeight: FontWeight.w800)),
          T('Zitakazoisha kabla mzigo ujao haujafika', style: TextStyle(fontSize: 12, color: mutedText)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => _openOrders('all'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const T('Maagizo'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 96), // room for the floating Rasimu button
          children: [
            // Which products: suggested, alerts, or all stock (to order anything).
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  for (final (v, label) in _views)
                    ButtonSegment(value: v, label: Text(_counts[v] == null ? tr(label) : '${tr(label)} ${_counts[v]}', overflow: TextOverflow.ellipsis)),
                ],
                selected: {_view},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: inkColor,
                  selectedForegroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                onSelectionChanged: (v) {
                  setState(() {
                    _view = v.first;
                    _filter.clear();
                  });
                  _load();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Text(
                switch (_view) {
                  'alerts' => tr('Zilizoisha, au zilizofika kiwango chako cha kuagiza. Weka idadi kwa unazotaka.'),
                  'all' => tr('Kila bidhaa dukani. Kuagiza ni uamuzi wako: weka idadi kwa yoyote.'),
                  _ => tr('Zitakazoisha kabla mzigo ujao haujafika. Idadi imependekezwa; ibadilishe ukipenda.'),
                },
                style: const TextStyle(fontSize: 12, color: mutedText),
              ),
            ),
            if (_view == 'all')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.filter_list), hintText: tr('Chuja kwa jina…'), isDense: true),
                ),
              ),
            // Said in words: how much to order, not a bare "7 / 14 / 30".
            const T('Agiza kiasi cha kutosha kwa:', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [for (final (d, label) in _covers) ButtonSegment(value: d, label: Text(tr(label)))],
                selected: {_cover},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: brandGreen,
                  selectedForegroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onSelectionChanged: (v) {
                  setState(() => _cover = v.first);
                  _load(fresh: true);
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: T('baada ya mzigo kufika', style: TextStyle(fontSize: 12, color: mutedText)),
            ),
            if (_open.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Material(
                  color: const Color(0xFFDDF3EA),
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: const Icon(Icons.local_shipping_outlined, color: brandGreen),
                    title: Text(tr('Maagizo :open yametumwa, yanasubiri kufika', {'open': _open.length}), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const T('Bidhaa zake hazitapendekezwa tena mpaka mzigo ufike · gusa kuona'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openOrders('sent'),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (_loading && _data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: AfyaLoader())),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: dangerRed))),
            if (!_loading && _error == null && groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: T('Hakuna bidhaa hapa. Angalia "Zote" kuagiza bidhaa yoyote.', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
              ),
            if (_draft != null) _draftCard(),
            if (_draft != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
                child: T('ONGEZA KUTOKA ORODHA HIZI: weka idadi, kisha ⋮ → "Weka zilizochaguliwa kwenye rasimu"',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
              ),
            for (final g in groups) _group(g),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _data == null ? null : _orderAnything,
              icon: const Icon(Icons.add),
              label: const T('Agiza bidhaa nyingine yoyote'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (groups.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(
                  tr('Idadi imehesabiwa kutoka mauzo ya siku 30, muda ambao msambazaji huchukua kuleta mzigo, na vifungashio alivyoleta mara ya mwisho. Gusa kifungashio kubadilisha (mfano kadi → boksi).'),
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _group(Map<String, dynamic> g) {
    final s = g['supplier'] as Map<String, dynamic>?;
    final lines = ((g['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final lastDays = g['last_delivery_days'];
    final lead = g['lead_days'];
    final note = s == null
        ? tr('Hazijawahi kuletwa na msambazaji anayejulikana')
        : lead == null
            ? tr('Umechagua mwenyewe')
            : '${g['lead_learned'] == true ? tr('Huleta kila siku ~:lead', {'lead': lead}) : tr('Muda wa kuleta: siku :lead (makadirio)', {'lead': lead})}'
                '${lastDays != null ? tr(' · mara ya mwisho siku :last_days zilizopita', {'last_days': lastDays}) : ''}';
    var total = 0;
    var priced = true;
    for (final l in lines) {
      // The last price is per the last packaging; a changed packaging has no price yet.
      final changed = _packOf.containsKey(asInt(l['product_id']));
      if (l['pack_cost'] == null || changed) priced = false;
      total += _chosen(l) * asInt(l['pack_cost']);
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: softCard(radius: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s == null ? tr('Bila msambazaji') : '${s['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(note, style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            if (_costs && priced && total > 0) Text('~${formatTsh(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              tooltip: tr('Orodha hii'),
              onSelected: (v) => _groupAction(v, lines, asInt(s?['id'])),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'supplier', child: T('Agiza zote kutoka kwa…')),
                PopupMenuItem(value: 'all', child: T('Chagua zote (1 ya kila moja)')),
                PopupMenuItem(value: 'none', child: T('Ondoa zote (weka 0)')),
                if (_draft != null) PopupMenuItem(value: 'todraft', child: T('Weka zilizochaguliwa kwenye rasimu')),
              ],
            ),
          ]),
        ),
        for (final l in lines) _line(l, asInt(s?['id'])),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: TextButton.icon(
            onPressed: () => _addProduct(asInt(s?['id'])),
            icon: const Icon(Icons.add),
            label: const T('Ongeza bidhaa'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: FilledButton.icon(
            onPressed: lines.any((l) => _chosen(l) > 0) ? () => _send(g) : null,
            icon: const Icon(Icons.send_rounded),
            label: Text(s == null ? tr('Andaa ujumbe') : tr('Tuma kwa :a', {'a': s['name']})),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
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
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2F5FA8), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const T('Rasimu: endelea kuhariri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2F5FA8))),
                Text(tr('Bidhaa :n · tuma kila msambazaji akiwa tayari', {'n': chosen}), style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            // "Zote kutoka": one supplier for every product of the draft (each can still be changed).
            TextButton(
              onPressed: () async {
                final k = await _askSupplier(tr('Bidhaa zote za rasimu kutoka kwa nani?'), _draftSupplier);
                if (k == null || !mounted) return;
                setState(() {
                  _draftSupplier = k;
                  for (final l in _draftLines) {
                    l['supplier_id'] = k;
                  }
                });
              },
              child: Text(tr('Zote: :a', {'a': s?['name'] ?? tr('chagua')})),
            ),
          ]),
        ),
        for (final k in keys) ...[
          Container(
            color: const Color(0xFFF1F5FC),
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${_supplierById(k)?['name'] ?? tr('Bila msambazaji bado')} · ${tr('bidhaa :n', {'n': _draftLines.where((l) => asInt(l['supplier_id']) == k).length})}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.tonal(
                onPressed: _savingDraft || !_draftLines.any((l) => asInt(l['supplier_id']) == k && _chosen(l) > 0) ? null : () => _sendDraftPart(k),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(_supplierById(k) == null ? tr('Tuma') : tr('Tuma kwa :a', {'a': _supplierById(k)!['name']}), overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          for (final l in _draftLines.where((l) => asInt(l['supplier_id']) == k)) _line(l, k, inDraft: true),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: TextButton.icon(
            onPressed: () => _addProduct(_draftSupplier, toDraft: true),
            icon: const Icon(Icons.add),
            label: const T('Ongeza bidhaa'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: FilledButton(
            onPressed: _savingDraft ? null : _saveDraft,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const T('Hifadhi rasimu'),
          ),
        ),
      ]),
    );
  }

  Widget _line(Map<String, dynamic> l, int supplierKey, {bool inDraft = false}) {
    final id = asInt(l['product_id']);
    final onHand = asInt(l['on_hand']);
    final days = l['days_left'];
    final onOrder = asInt(l['on_order']);
    final units = _units(l);
    final reason = '${l['reason']}';
    final (packName, packSize) = _pack(l);
    final stock = tr('zipo :a', {'a': describeStock(onHand, units)});
    final (why, color) = switch (reason) {
      'out' => (tr('Imeisha'), dangerRed),
      'runs_out' => (tr('Itaisha baada ya siku :days:a · :stock', {'days': days, 'a': asInt(days) < 2 ? '!' : '', 'stock': stock}), asInt(days) < 2 ? dangerRed : warnAmber),
      'low' => (tr('Chini ya kiwango cha kuagiza · :stock', {'stock': stock}), warnAmber),
      'ok' => (tr('Inatosha · :stock', {'stock': stock}), mutedText),
      'draft' => (tr('Kwenye rasimu · :stock', {'stock': stock}), mutedText),
      _ => (tr('Umeongeza mwenyewe · :stock', {'stock': stock}), mutedText),
    };
    final n = _chosen(l);
    final base = units.isEmpty ? '' : units.first.name;

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE3EDE8)))),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        InkWell(
          onTap: () async {
            if (!inDraft) return _moveLine(l, supplierKey);
            final k = await _askSupplier(tr('Agiza :a kutoka kwa nani?', {'a': l['name']}), supplierKey);
            if (k != null && mounted) setState(() => l['supplier_id'] = k);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Kutoka: :a', {'a': _supplierById(supplierKey)?['name'] ?? tr('bila msambazaji')}),
                  style: const TextStyle(fontSize: 12, color: brandGreen, fontWeight: FontWeight.w700)),
              const Icon(Icons.arrow_drop_down, size: 18, color: brandGreen),
            ]),
          ),
        ),
        Text(why, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        if (onOrder > 0) Text(tr('Imeshaagizwa: :a', {'a': describeStock(onOrder, units)}), style: const TextStyle(fontSize: 12, color: mutedText)),
        const SizedBox(height: 4),
        Row(children: [
          // The packaging is a button: strips last time, boxes now.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _choosePack(l),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(
                  packSize > 1 ? '${unitLabel(packName)} (${unitLabel(base, packSize)} $packSize)' : unitLabel(packName),
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Punguza'),
            onPressed: n > 0 ? () => setState(() => _packs[id] = n - 1) : null,
            icon: const Icon(Icons.remove_circle_outline, color: brandGreen),
          ),
          SizedBox(
            width: 40,
            child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: tr('Ongeza'),
            onPressed: () => setState(() => _packs[id] = n + 1),
            icon: const Icon(Icons.add_circle, color: brandGreen),
          ),
        ]),
      ]),
    );
  }
}

/// Search the shop's products to order any of them.
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
  List<Product> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final d = await widget.api.get('products', query: {'q': q.trim()}) as List;
        if (mounted && q == _q.text) setState(() => _results = d.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList());
      } on ApiException {
        // keep the old list
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const T('Agiza bidhaa gani?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (q) {
              setState(() {}); // the "Bidhaa mpya: …" button shows what was typed
              _search(q);
            },
            decoration: InputDecoration(labelText: tr('Tafuta dawa'), prefixIcon: Icon(Icons.search)),
          ),
          Expanded(
            child: ListView(children: [
              for (final p in _results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Zipo: :a', {'a': describeStock(p.onHand, p.units)})),
                  trailing: const Icon(Icons.add_circle_outline, color: brandGreen),
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ]),
          ),
          if (widget.canCreate)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(_q.text.trim()),
              icon: const Icon(Icons.add_box_outlined),
              label: Text(_q.text.trim().length >= 2 ? tr('Bidhaa mpya: :a', {'a': _q.text.trim()}) : tr('Bidhaa mpya (haipo dukani)')),
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
