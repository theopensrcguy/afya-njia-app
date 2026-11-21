import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/scan_once.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../stock/unit_picker.dart';
import 'new_product.dart';
import 'new_product_screen.dart';
import 'receive_line.dart';
import '../../core/i18n.dart';

/// One packaging choice for this delivery: "Boksi · 100".
class _Pack {
  const _Pack(this.name, this.size);
  final String name;
  final int size;
  bool same(_Pack o) => name == o.name && size == o.size;
}

/// "Ongeza bidhaa": pick the product, then how it came (packaging), how many,
/// batch, expiry (month + year, as printed) and the price per pack.
///
/// Most of it is filled in from what this supplier sent last time, so the
/// usual line is: product → number of packs → batch → expiry → done.
class ReceiveLineScreen extends StatefulWidget {
  const ReceiveLineScreen({
    super.key,
    required this.api,
    this.supplierId,
    this.supplierName,
    this.initial,
    this.canPrice = false,
    this.drafts = const [],
  });

  final ApiClient api;

  /// May set selling prices (edit_prices). Without it, a new product's
  /// prices are left for whoever confirms the delivery.
  final bool canPrice;

  /// New products already on this delivery: a second batch of one picks it
  /// from here instead of creating it twice.
  final List<NewProductDraft> drafts;
  final int? supplierId;
  final String? supplierName;

  /// Editing an existing line instead of adding one.
  final ReceiveLine? initial;

  @override
  State<ReceiveLineScreen> createState() => _ReceiveLineScreenState();
}

class _ReceiveLineScreenState extends State<ReceiveLineScreen> {
  // ---- product search
  final _search = TextEditingController();
  Timer? _debounce;
  List<Product> _results = [];
  List<(Map<String, dynamic>, Map<String, dynamic>)> _catalogue = []; // (entry, variant) the shop doesn't have yet
  bool _searching = false;

  // ---- the line
  Product? _product;
  NewProductDraft? _draft; // set when this product arrives for the first time
  String? _barcode; // scanned on the box: learned for the counter
  int? _linkId; // "Ndiyo, ni hiyo": link this catalogue entry to the existing product
  String? _linkVariant;
  Map<String, dynamic>? _last; // what was delivered last time (packaging, price)
  final List<_Pack> _packs = [];
  _Pack? _pack;
  int _count = 1;
  final _batch = TextEditingController();
  final _cost = TextEditingController();
  int? _year;
  int? _month;
  String? _error;

  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    if (l != null) {
      _product = l.product;
      _draft = l.newProduct;
      _linkId = l.linkCatalogueItemId;
      _linkVariant = l.linkVariant;
      _barcode = l.barcode;
      _buildPacks();
      _pack = _packs.firstWhere((p) => p.same(_Pack(l.packName, l.packSize)), orElse: () {
        final custom = _Pack(l.packName, l.packSize);
        _packs.add(custom);
        return custom;
      });
      _count = l.packs;
      _batch.text = l.batch;
      _cost.text = groupDigits(l.packCost);
      _year = l.expiryYear;
      _month = l.expiryMonth;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch(''));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _batch.dispose();
    _cost.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- searching

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    try {
      // 1. the shop's own products; 2. the catalogue, for what it doesn't have yet.
      final data = await widget.api.get('products', query: {'q': q}) as List;
      final cat = q.trim().length >= 2 ? await widget.api.get('catalogue', query: {'q': q.trim()}) as Map<String, dynamic> : null;
      if (!mounted || q != _search.text) return;
      setState(() {
        _results = data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
        _catalogue = [
          for (final item in ((cat?['results'] as List?) ?? const []).cast<Map<String, dynamic>>())
            for (final v in ((item['variants'] as List?) ?? const []).cast<Map<String, dynamic>>())
              // "unayo": already one of the shop's products, so it shows above instead.
              if (v['own_product_id'] == null) (item, v),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Scan the box: a known code picks the product; an unknown one is kept
  /// and learned for whatever product is chosen next.
  Future<void> _scan() async {
    final code = await scanOnce(context);
    if (code == null || !mounted) return;
    _barcode = code;
    try {
      final res = await widget.api.get('products/barcode/$code') as Map<String, dynamic>;
      if (!mounted) return;
      await _choose(Product.fromJson(res));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'unknown_barcode' ? null : e.message);
      if (e.code == 'unknown_barcode') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: T('Barcode mpya: chagua au ongeza bidhaa yake. Itakumbukwa kwa kaunta.'),
        ));
      }
    }
  }

  /// "+ Bidhaa mpya": the name first. The shop's products and the catalogue are
  /// searched with it (a correct catalogue name beats a typed one, and a product
  /// the shop already has must not be made twice); with no match, straight to the form.
  Future<void> _newProductButton() async {
    final name = await askText(context,
        title: tr('Bidhaa mpya'), label: tr('Jina la dawa (generic)'), hint: tr('mfano Paracetamol 500mg'), initial: _search.text.trim(), required: true);
    final q = (name ?? '').trim();
    if (q.length < 2 || !mounted) return;
    _search.text = q;
    await _runSearch(q);
    if (!mounted) return;
    if (_results.isEmpty && _catalogue.isEmpty) return _newProduct(typed: q);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('Zinazofanana zimepatikana: chagua hapa chini. Kama sio, bonyeza "Ongeza :a kama bidhaa mpya" mwishoni.', {'a': q})),
    ));
  }

  /// A product arriving for the first time: from the catalogue, or typed.
  Future<void> _newProduct({Map<String, dynamic>? item, Map<String, dynamic>? variant, String? typed}) async {
    FocusScope.of(context).unfocus();
    final choice = await Navigator.of(context).push<NewProductChoice>(MaterialPageRoute(
      builder: (_) => NewProductScreen(api: widget.api, canPrice: widget.canPrice, item: item, variant: variant, typedName: typed),
    ));
    if (choice == null || !mounted) return;
    _apply(choice);
  }

  Future<void> _editDraft() async {
    final choice = await Navigator.of(context).push<NewProductChoice>(MaterialPageRoute(
      builder: (_) => NewProductScreen(api: widget.api, canPrice: widget.canPrice, initial: _draft),
    ));
    if (choice?.draft == null || !mounted) return;
    setState(() {
      final keep = _pack;
      _product = _draft!.asProduct();
      _buildPacks();
      if (keep != null && !_packs.any((x) => x.same(keep))) _packs.add(keep);
      _pack = keep ?? _packs.last;
    });
  }

  void _apply(NewProductChoice choice) {
    if (choice.existing != null) {
      // "Ndiyo, ni hiyo": no new product; the catalogue name becomes its official one.
      _linkId = choice.linkCatalogueItemId;
      _linkVariant = choice.linkVariant;
      _choose(choice.existing!, keepLink: true);
      return;
    }
    _chooseDraft(choice.draft!);
  }

  void _chooseDraft(NewProductDraft d) {
    FocusScope.of(context).unfocus();
    setState(() {
      _draft = d;
      _linkId = null;
      _linkVariant = null;
      _last = null;
      _product = d.asProduct();
      _error = null;
      _buildPacks();
      _pack = _packs.last; // deliveries usually come in the biggest pack
    });
  }

  Future<void> _choose(Product p, {bool keepLink = false}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _draft = null;
      if (!keepLink) {
        _linkId = null;
        _linkVariant = null;
      }
      _product = p;
      _error = null;
      _buildPacks();
      _pack = _packs.length > 1 ? _packs.last : _packs.first; // biggest pack: deliveries usually come in boxes
    });
    // What came last time, from this supplier if possible.
    try {
      final res = await widget.api.get('purchases/last-terms', query: {
        'product_id': '${p.id}',
        if (widget.supplierId != null) 'supplier_id': '${widget.supplierId}',
      }) as Map<String, dynamic>;
      final last = res['last'] as Map<String, dynamic>?;
      if (!mounted || last == null) return;
      setState(() {
        _last = last;
        final lastPack = _Pack('${last['pack_name'] ?? p.units.first.name}', asInt(last['pack_size']));
        final match = _packs.where((x) => x.same(lastPack)).toList();
        if (match.isEmpty) _packs.add(lastPack);
        _pack = match.isEmpty ? lastPack : match.first;
        _fillCostFromLast();
      });
    } on ApiException {
      // No memory is fine: the person types the price.
    }
  }

  /// Packaging choices: the product's own units (kidonge, kadi, boksi), plus
  /// what was delivered last time if different, plus "Nyingine" (added on tap).
  void _buildPacks() {
    _packs
      ..clear()
      ..addAll(_product!.units.map((u) => _Pack(u.name, u.baseQuantity)));
  }

  /// Same packaging as last time = same price as last time; otherwise the
  /// last price per tablet × this pack's size, as a starting point.
  void _fillCostFromLast() {
    final last = _last;
    final pack = _pack;
    if (last == null || pack == null) return;
    final sameSize = asInt(last['pack_size']) == pack.size;
    _cost.text = groupDigits(sameSize ? asInt(last['pack_cost']) : asInt(last['unit_cost']) * pack.size);
  }

  Future<void> _otherPack() async {
    final name = await pickUnitName(context, api: widget.api, title: tr('Kimekuja kwa kifungashio gani?'));
    if (name == null || !mounted) return;
    final base = unitLabel(_product!.units.first.name, 2);
    final size = await askText(context,
        title: tr(':a moja ina :base ngapi?', {'a': unitLabel(name), 'base': base}), label: tr('Idadi ya :base', {'base': base}), digitsOnly: true, required: true);
    final n = int.tryParse(size ?? '') ?? 0;
    if (n < 1 || !mounted) return;
    setState(() {
      final p = _Pack(name, n);
      _packs.add(p);
      _pack = p;
      _fillCostFromLast();
    });
  }

  // ---------------------------------------------------------------- saving

  void _save() {
    final batch = _batch.text.trim().toUpperCase();
    final cost = moneyValue(_cost.text);
    String? error;
    if (_pack == null) {
      error = tr('Chagua kimekuja kwa kifungashio gani.');
    } else if (batch.isEmpty) {
      error = tr('Andika namba ya batch (iko kwenye boksi).');
    } else if (_year == null || _month == null) {
      error = tr('Chagua mwezi na mwaka wa kuisha (EXP).');
    } else if (_monthsLeft() < 0) {
      error = tr('Batch hii imeshaisha muda. Haipokelewi.');
    } else if (cost == null) {
      error = tr('Weka bei ya kununua kwa :a.', {'a': unitLabel(_pack!.name)});
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(ReceiveLine(
      chosenProduct: _product!,
      packName: _pack!.name,
      packSize: _pack!.size,
      packs: _count,
      packCost: cost!,
      batch: batch,
      expiryYear: _year!,
      expiryMonth: _month!,
      newProduct: _draft,
      barcode: _barcode,
      linkCatalogueItemId: _linkId,
      linkVariant: _linkVariant,
    ));
  }

  /// Whole months from this month to the expiry month (0 = expires this month).
  int _monthsLeft() {
    final now = DateTime.now();
    return (_year! - now.year) * 12 + (_month! - now.month);
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? tr('Ongeza bidhaa') : tr('Badilisha bidhaa')),
        backgroundColor: pageBackground,
      ),
      body: _product == null ? _searchView() : _form(),
    );
  }

  Widget _searchView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextField(
          controller: _search,
          autofocus: true,
          onChanged: _onSearch,
          decoration: InputDecoration(
            labelText: tr('Tafuta dawa iliyokuja'),
            prefixIcon: const Icon(Icons.search),
            helperText: _barcode == null ? null : tr('Barcode :barcode itaunganishwa na bidhaa utakayochagua', {'barcode': _barcode}),
            suffixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(tooltip: tr('Skani boksi'), onPressed: _scan, icon: const Icon(Icons.qr_code_scanner, color: brandGreen)),
          ),
        ),
      ),
      if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
      Expanded(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            // Easy to find: a product the shop never had (generic name, brand, units, prices).
            OutlinedButton.icon(
              onPressed: _newProductButton,
              icon: const Icon(Icons.add_box_outlined),
              label: const T('Bidhaa mpya (haipo dukani)'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
            const SizedBox(height: 4),
            // New products already on this delivery (a second batch of one).
            if (widget.drafts.isNotEmpty) ...[
              _section(tr('MPYA KWENYE MZIGO HUU')),
              for (final d in widget.drafts)
                _tile(
                  title: d.name,
                  subtitle: tr('Bidhaa mpya · :a', {'a': d.units.map((u) => unitLabel(u.name)).join(', ')}),
                  badge: tr('mpya'),
                  onTap: () => _chooseDraft(d),
                ),
            ],
            // 1. The shop's own products always come first.
            if (_results.isNotEmpty) _section(tr('BIDHAA ZAKO')),
            for (final p in _results)
              _tile(
                title: p.name,
                subtitle: tr('Iliyopo: :a', {'a': describeStock(p.onHand, p.units)}),
                onTap: () => _choose(p),
              ),
            // 2. Then the catalogue: correct names for what isn't in stock yet.
            if (_catalogue.isNotEmpty) ...[
              _section(tr('KATALOGI · BADO HUNA HIZI')),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: T('Ukichagua, bidhaa mpya inaundwa kwa jina sahihi.', style: TextStyle(fontSize: 12, color: mutedText)),
              ),
              for (final (item, v) in _catalogue)
                _tile(
                  title: '${v['name']}',
                  subtitle: _catalogueLine(item),
                  badge: tr('+ Mpya'),
                  onTap: () => _newProduct(item: item, variant: v),
                ),
            ],
            // 3. Last resort: typed by hand, flagged for the owner.
            if (_search.text.trim().length >= 2) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF9CC9B8)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const T('Haipo kwenye katalogi pia?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const T('Kwa vitu visivyo dawa (vipodozi, glovu, pamba). Mwenye duka ataona alama "nje ya katalogi".',
                      style: TextStyle(fontSize: 12, color: mutedText)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _newProduct(typed: _search.text.trim()),
                    child: Text(tr('Ongeza ":a" kama bidhaa mpya', {'a': _search.text.trim()})),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  String _catalogueLine(Map<String, dynamic> item) {
    const sources = {'tmda': 'TMDA', 'nemlit': 'NEMLIT', 'supplies': 'Vifaa tiba'};
    final brandOf = item['source'] == 'tmda' && item['ingredient'] != null ? ' · ${item['ingredient']}' : '';
    return '${sources[item['source']] == null ? item['source'] : tr(sources[item['source']]!)}$brandOf';
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText, letterSpacing: 0.4)),
      );

  Widget _tile({required String title, required String subtitle, String? badge, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle),
            trailing: badge == null
                ? const Icon(Icons.chevron_right)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFDDF3EA), borderRadius: BorderRadius.circular(10)),
                    child: Text(badge, style: const TextStyle(color: brandGreen, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
            onTap: onTap,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: softCard(radius: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _form() {
    final p = _product!;
    final base = p.units.first.name;
    final pack = _pack;
    final cost = moneyValue(_cost.text) ?? 0;
    final total = cost * _count;

    return Column(children: [
      Expanded(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          children: [
            // Product
            _card([
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_draft != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFDDF3EA), borderRadius: BorderRadius.circular(8)),
                        child: Text(_draft!.offCatalogue ? tr('BIDHAA MPYA · nje ya katalogi') : tr('BIDHAA MPYA'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: brandGreen)),
                      ),
                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      _draft != null
                          ? (_draft!.hasPrices ? tr('Itaundwa mzigo ukihifadhiwa') : tr('Bei ya kuuza: mwenye duka ataiweka akithibitisha'))
                          : tr('Iliyopo: :a', {'a': describeStock(p.onHand, p.units)}),
                      style: const TextStyle(fontSize: 12, color: mutedText),
                    ),
                  ]),
                ),
                if (_draft != null) TextButton(onPressed: _editDraft, child: const T('Hariri')),
                if (widget.initial == null)
                  TextButton(
                    onPressed: () => setState(() {
                      _product = null;
                      _draft = null;
                      _linkId = null;
                      _linkVariant = null;
                    }),
                    child: const T('Badilisha'),
                  ),
              ]),
            ]),

            // Packaging + how many
            _card([
              _label('IMEKUJA KWENYE'),
              if (_last != null)
                Text(
                  tr(':when: :pack ya :base :size, :cost', {
                    'when': _last!['from_this_supplier'] == true
                        ? tr('Mara ya mwisho :supplier', {'supplier': widget.supplierName ?? tr('msambazaji huyu')})
                        : tr('Mzigo wa mwisho'),
                    'pack': _last!['pack_name'] == null ? unitLabel(base, 2) : unitLabel('${_last!['pack_name']}'),
                    'base': unitLabel(base, 2),
                    'size': _last!['pack_size'],
                    'cost': formatTsh(asInt(_last!['pack_cost'])),
                  }),
                  style: const TextStyle(fontSize: 12, color: mutedText),
                ),
              const SizedBox(height: 10),
              // Packs as equal tiles: the name, and what's inside it.
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth > 420 ? 4 : 3;
                final w = (box.maxWidth - (cols - 1) * 8) / cols;
                Widget tile(String name, String size, bool on, VoidCallback onTap) => SizedBox(
                      width: w,
                      child: Material(
                        color: on ? const Color(0xFFE7F6EF) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: on ? brandGreen : const Color(0xFFDCE5E1), width: on ? 1.8 : 1.2),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(size, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: mutedText)),
                            ]),
                          ),
                        ),
                      ),
                    );
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in _packs)
                    tile(unitLabel(x.name), x.size == 1 ? tr('kimoja') : '${unitLabel(base, x.size)} ${x.size}', pack != null && pack.same(x), () => setState(() {
                          _pack = x;
                          _fillCostFromLast();
                        })),
                  tile(tr('+ Nyingine'), tr('kifungashio kingine'), false, _otherPack),
                ]);
              }),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Text(tr(':a ngapi?', {'a': pack == null ? tr('Ngapi') : unitLabel(pack.name, 2)}),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                _stepButton(Icons.remove, _count > 1 ? () => setState(() => _count--) : null),
                InkWell(
                  onTap: () async {
                    final v = await askText(context, title: tr('Idadi'), label: tr('Idadi'), initial: '$_count', digitsOnly: true, required: true);
                    final n = int.tryParse(v ?? '') ?? 0;
                    if (n > 0 && mounted) setState(() => _count = n);
                  },
                  child: SizedBox(
                    width: 52,
                    child: Text('$_count', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ),
                _stepButton(Icons.add, () => setState(() => _count++), filled: true),
              ]),
              if (pack != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(12)),
                  child: Text('= ${describeStock(_count * pack.size, p.units)} (${unitLabel(base, 2)} ${_count * pack.size})',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),

            // Batch
            _card([
              _label('KWENYE BOKSI'),
              TextField(
                controller: _batch,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('Namba ya batch (BATCH / LOT)')),
              ),
            ]),

            // Expiry
            _card([
              Row(children: [
                const Expanded(child: T('Inaisha (EXP)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                if (_year != null && _month != null)
                  Text('${_month.toString().padLeft(2, '0')}/$_year',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: brandGreen)),
              ]),
              const SizedBox(height: 10),
              _yearChips(),
              const SizedBox(height: 8),
              _monthGrid(),
              if (_year != null && _month != null && _monthsLeft() >= 0 && _monthsLeft() < 6)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: T('Muda mfupi: inaisha ndani ya miezi 6. Una uhakika?',
                      style: TextStyle(color: warnAmber, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ]),

            // Cost, against last time and the selling price.
            _card([
              _label('BEI'),
              TextField(
                controller: _cost,
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInput()],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Bei ya kununua kwa :a (TSh)', {'a': pack == null ? tr('kifungashio') : unitLabel(pack.name)}),
                  helperText: _sellingHint(cost),
                ),
              ),
              if (_compare(cost) case final rows? when rows.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF5F8F7), borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    for (final (label, value, color) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: mutedText))),
                          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
                        ]),
                      ),
                  ]),
                ),
            ]),
            if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      // The line's total and the one button, in a dark bar that stays put.
      SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF14211D),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x44142A23), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  pack == null || cost == 0 ? tr('Jumla ya bidhaa hii') : '${unitLabel(pack.name, _count)} $_count × ${formatTsh(cost)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB7C7C1)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatTsh(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
            ),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3DDC97),
                foregroundColor: const Color(0xFF0E3B31),
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(widget.initial == null ? tr('Weka kwenye mzigo') : tr('Hifadhi mabadiliko'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(tr(text), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: mutedText)),
      );

  /// Last time's price for this pack, the selling price and the profit per
  /// smallest unit: the three things to check before accepting a price.
  List<(String, String, Color)>? _compare(int cost) {
    final pack = _pack;
    if (pack == null || _product == null) return null;
    final base = _product!.units.first;
    final out = <(String, String, Color)>[];
    final last = _last;
    if (last != null && asInt(last['pack_size']) == pack.size && asInt(last['pack_cost']) > 0) {
      final lc = asInt(last['pack_cost']);
      final diff = cost == 0 ? 0 : ((cost - lc) * 100 / lc).round();
      out.add((
        last['from_this_supplier'] == true ? tr('Mara ya mwisho (:s)', {'s': widget.supplierName ?? tr('msambazaji huyu')}) : tr('Mzigo wa mwisho'),
        '${formatTsh(lc)}${diff == 0 ? '' : (diff > 0 ? '  ↑ $diff%' : '  ↓ ${-diff}%')}',
        diff > 0 ? dangerRed : inkColor,
      ));
    }
    if (base.price > 0) {
      out.add((tr('Unauza kwa'), '${formatTsh(base.price)} / ${unitLabel(base.name)}', inkColor));
      if (cost > 0) {
        final per = cost / pack.size;
        final profit = base.price - per;
        out.add((
          tr('Faida kwa :u', {'u': unitLabel(base.name)}),
          '${formatTsh(profit.round())} · ${(profit / base.price * 100).round()}%',
          profit <= 0 ? dangerRed : brandGreen,
        ));
      }
    }
    return out;
  }

  /// "TSh 20 kwa kidonge · unauza TSh 50": is this delivery worth it?
  String? _sellingHint(int cost) {
    final pack = _pack;
    if (pack == null || cost == 0) return null;
    final perBase = cost / pack.size;
    final sell = _product!.units.first.price;
    final base = unitLabel(_product!.units.first.name);
    final cost1 = tr('TSh :a kwa :base', {'a': perBase.toStringAsFixed(perBase < 10 ? 1 : 0), 'base': base});
    if (sell == 0) return cost1; // new product, price set by the owner later
    final hint = tr(':cost · unauza TSh :sell', {'cost': cost1, 'sell': sell});
    return perBase >= sell ? tr(':hint · HASARA!', {'hint': hint}) : hint;
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap, {bool filled = false}) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton.filled(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: filled ? brandGreen : mintSoft,
            foregroundColor: filled ? Colors.white : brandGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _yearChips() {
    final now = DateTime.now().year;
    return Row(children: [
      for (var y = now; y <= now + 4; y++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: y == now + 4 ? 0 : 6),
            child: Material(
              color: _year == y ? brandGreen : mintSoft,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _year = y),
                child: SizedBox(
                  height: 38,
                  child: Center(
                    child: Text('$y',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _year == y ? Colors.white : inkColor)),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  static const _monthNames = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];

  Widget _monthGrid() {
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.6,
      children: [
        for (var m = 1; m <= 12; m++)
          Material(
            color: _month == m ? brandGreen : mintSoft,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _month = m),
              child: Center(
                child: Text(tr(_monthNames[m - 1]),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _month == m ? Colors.white : inkColor)),
              ),
            ),
          ),
      ],
    );
  }
}
