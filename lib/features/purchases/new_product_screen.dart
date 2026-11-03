import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'new_product.dart';

/// "Bidhaa mpya": a product arriving for the first time.
///
/// 1. The name comes from the catalogue and can't be edited (or is typed for
///    things outside the catalogue).
/// 2. "Je, ni hii unayo tayari?": the server looks for the same medicine
///    among the shop's products (Amoxyl = amoxicillin). Nothing continues
///    until that question is answered, because a duplicate silently splits
///    a product's sales and stock in two.
/// 3. How it is sold, and its prices (only with edit_prices; otherwise the
///    owner sets them when confirming the delivery).
class NewProductScreen extends StatefulWidget {
  const NewProductScreen({
    super.key,
    required this.api,
    required this.canPrice,
    this.item,
    this.variant,
    this.typedName,
    this.initial,
  });

  final ApiClient api;
  final bool canPrice;

  /// From the catalogue: the entry and the chosen variant {label, name, strength}.
  final Map<String, dynamic>? item;
  final Map<String, dynamic>? variant;

  /// Outside the catalogue: what was typed in the search box.
  final String? typedName;

  /// Editing a draft already on this delivery.
  final NewProductDraft? initial;

  @override
  State<NewProductScreen> createState() => _NewProductScreenState();
}

class _NewProductScreenState extends State<NewProductScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? widget.typedName ?? '');
  late final _brand = TextEditingController(text: widget.initial?.brandName ?? '');
  final Map<int, TextEditingController> _prices = {}; // by base quantity

  List<Map<String, dynamic>> _similar = [];
  bool _checking = true;
  bool _differentConfirmed = false;

  late String _baseUnit;
  late List<DraftUnit> _packs; // everything bigger than the base unit
  int _reorderPacks = 0; // in the first pack (or base) unit
  String? _error;

  bool get _fromCatalogue => widget.item != null || (widget.initial?.catalogueItemId != null);

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d != null) {
      _baseUnit = d.units.first.name;
      _packs = [for (final u in d.units.skip(1)) DraftUnit(name: u.name, baseQuantity: u.baseQuantity, price: u.price)];
      for (final u in d.units) {
        if (u.price != null) _priceFor(u.baseQuantity).text = '${u.price}';
      }
      final first = _packs.isEmpty ? 1 : _packs.first.baseQuantity;
      _reorderPacks = d.reorderLevel ~/ first;
      _differentConfirmed = true; // already answered when the draft was made
      _checking = false;
    } else {
      _baseUnit = _guessBaseUnit();
      // Most tablets and capsules also sell by the kadi; the size is set below.
      _packs = _baseUnit == 'kidonge' ? [DraftUnit(name: 'kadi', baseQuantity: 10)] : [];
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkSimilar());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _priceFor(int size) => _prices.putIfAbsent(size, TextEditingController.new);

  /// From the catalogue's form words: capsule/tablet → kidonge, syrup → chupa...
  String _guessBaseUnit() {
    final words = '${widget.item?['form'] ?? ''} ${widget.variant?['label'] ?? ''} ${widget.item?['source'] ?? ''}'.toLowerCase();
    if (RegExp(r'tablet|capsule|caplet').hasMatch(words)) return 'kidonge';
    if (RegExp(r'syrup|suspension|solution|mixture|drops|elixir').hasMatch(words)) return 'chupa';
    if (RegExp(r'injection|vial|ampoule').hasMatch(words)) return 'sindano';
    if (RegExp(r'cream|ointment|gel').hasMatch(words)) return 'tube';
    if (RegExp(r'sachet|powder').hasMatch(words)) return 'pakiti';
    if (words.contains('supplies') || widget.item == null) return 'kipande';
    return 'kidonge';
  }

  Future<void> _checkSimilar() async {
    try {
      final item = widget.item;
      final data = await widget.api.get('products/similar', query: {
        if (item != null) 'catalogue_item_id': '${item['id']}',
        if (item != null && widget.variant != null) 'variant': '${widget.variant!['label']}',
        if (item == null) 'name': _name.text.trim(),
      }) as List;
      if (mounted) setState(() => _similar = data.cast<Map<String, dynamic>>());
    } on ApiException {
      // The check is a help, not a gate on the network: carry on without it.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ------------------------------------------------------------- units

  Future<void> _pickBase() async {
    final name = await _unitSheet('Inahesabiwa kwa nini? (kipimo kidogo kabisa)');
    if (name != null && mounted) setState(() => _baseUnit = name);
  }

  Future<void> _addPack() async {
    final name = await _unitSheet('Kipimo kingine');
    if (name == null || !mounted) return;
    final base = unitLabel(_baseUnit, 2);
    final v = await askText(context,
        title: '${unitLabel(name)} moja ina $base ngapi?', label: 'Idadi ya $base', digitsOnly: true, required: true);
    final n = int.tryParse(v ?? '') ?? 0;
    if (n < 2 || !mounted) return;
    if (_packs.any((p) => p.baseQuantity == n || p.name == name)) {
      setState(() => _error = 'Kipimo hicho tayari kipo.');
      return;
    }
    setState(() {
      _packs = [..._packs, DraftUnit(name: name, baseQuantity: n)]..sort((a, b) => a.baseQuantity.compareTo(b.baseQuantity));
      _error = null;
    });
  }

  Future<void> _changeSize(DraftUnit u) async {
    final base = unitLabel(_baseUnit, 2);
    final v = await askText(context,
        title: '${unitLabel(u.name)} moja ina $base ngapi?', label: 'Idadi ya $base', initial: '${u.baseQuantity}', digitsOnly: true, required: true);
    final n = int.tryParse(v ?? '') ?? 0;
    if (n < 2 || !mounted) return;
    setState(() {
      final old = _prices.remove(u.baseQuantity);
      u.baseQuantity = n;
      if (old != null) _prices[n] = old;
      _packs.sort((a, b) => a.baseQuantity.compareTo(b.baseQuantity));
    });
  }

  Future<String?> _unitSheet(String title) => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cardColor,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              for (final (n, label) in standardUnits) ListTile(title: Text(label), onTap: () => Navigator.of(sheet).pop(n)),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------- finish

  void _save() {
    final name = _fromCatalogue ? (widget.initial?.name ?? '${widget.variant?['name'] ?? widget.item?['name']}') : _name.text.trim();
    String? error;
    if (name.isEmpty) {
      error = 'Andika jina la bidhaa.';
    } else if (_similar.isNotEmpty && !_differentConfirmed) {
      error = 'Jibu swali la njano kwanza.';
    }
    final units = [DraftUnit(name: _baseUnit, baseQuantity: 1), ..._packs];
    if (error == null && widget.canPrice) {
      for (final u in units) {
        final p = int.tryParse(_priceFor(u.baseQuantity).text.trim());
        if (p == null || p < 1) {
          error = 'Weka bei ya kuuza kwa ${unitLabel(u.name)}.';
          break;
        }
        u.price = p;
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final firstPack = _packs.isEmpty ? 1 : _packs.first.baseQuantity;
    final d = widget.initial;
    if (d != null) {
      // Same object: every line of this delivery that uses it sees the change.
      d
        ..name = name
        ..brandName = _brand.text.trim()
        ..units = units
        ..reorderLevel = _reorderPacks * firstPack;
      Navigator.of(context).pop(NewProductChoice.draft(d));
      return;
    }
    Navigator.of(context).pop(NewProductChoice.draft(NewProductDraft(
      name: name,
      catalogueItemId: widget.item == null ? null : asInt(widget.item!['id']),
      variant: widget.variant == null ? null : '${widget.variant!['label']}',
      source: widget.item == null ? null : '${widget.item!['source']}',
      brandName: _brand.text.trim(),
      units: units,
      reorderLevel: _reorderPacks * firstPack,
    )));
  }

  void _useExisting(Map<String, dynamic> p) {
    final item = widget.item;
    Navigator.of(context).pop(NewProductChoice.existing(
      Product.fromJson(p),
      // Only a catalogue pick has an official name to link.
      linkCatalogueItemId: item == null ? null : asInt(item['id']),
      linkVariant: item == null ? null : '${widget.variant?['label'] ?? ''}',
    ));
  }

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bidhaa mpya'), backgroundColor: pageBackground),
      body: Column(children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              _nameCard(),
              if (_checking)
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Row(children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Inaangalia kama unayo tayari…', style: TextStyle(color: mutedText)),
                  ]),
                ),
              if (_similar.isNotEmpty && !_differentConfirmed) _similarCard(),
              if (_similar.isNotEmpty && _differentConfirmed && widget.initial == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('Imewekwa: tofauti na ${_similar.first['name']}.',
                          style: const TextStyle(fontSize: 12, color: mutedText)),
                    ),
                    TextButton(onPressed: () => setState(() => _differentConfirmed = false), child: const Text('Badilisha')),
                  ]),
                ),
              _card([
                TextField(
                  controller: _brand,
                  decoration: const InputDecoration(
                    labelText: 'Jina la kibiashara (si lazima)',
                    hintText: 'mfano: Amoxil',
                    helperText: 'Wateja wakiuliza kwa jina hili, utafutaji utaipata.',
                  ),
                ),
              ]),
              _unitsCard(),
              widget.canPrice ? _pricesCard() : _noPriceCard(),
              _reorderCard(),
              if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: FilledButton(
              onPressed: _checking ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: Text(widget.initial == null ? 'Endelea: kifungashio, batch, EXP' : 'Hifadhi'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: softCard(radius: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _nameCard() {
    const sources = {'tmda': 'TMDA', 'nemlit': 'NEMLIT', 'supplies': 'VIFAA TIBA'};
    final src = widget.item?['source'] ?? widget.initial?.source;
    if (_fromCatalogue) {
      return _card([
        Text('KUTOKA KATALOGI YA ${sources[src] ?? 'TMDA'}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: brandGreen, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        Text(widget.initial?.name ?? '${widget.variant?['name'] ?? widget.item?['name']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const Text('Jina hili halibadilishwi', style: TextStyle(fontSize: 12, color: mutedText)),
      ]);
    }
    return _card([
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFFBEFD6), borderRadius: BorderRadius.circular(8)),
        child: const Text('nje ya katalogi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: warnAmber)),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Jina la bidhaa', helperText: 'Mwenye duka ataliona na anaweza kulisahihisha.'),
      ),
    ]);
  }

  Widget _similarCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFBEFD6), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: warnAmber),
          SizedBox(width: 8),
          Text('Je, ni hii unayo tayari?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF6B4100))),
        ]),
        const SizedBox(height: 4),
        const Text('Bidhaa moja ikiandikwa mara mbili, mauzo na hisa yake vinagawanyika.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B4100))),
        for (final p in _similar) ...[
          const SizedBox(height: 10),
          Text('${p['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF6B4100))),
          Text(
            '${p['reason'] == 'looks_like' ? 'Jina linafanana' : 'Dawa ile ile'} · kwenye hisa: '
            '${describeStock(asInt(p['on_hand']), Product.fromJson(p).units)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B4100)),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: () => _useExisting(p),
            style: FilledButton.styleFrom(backgroundColor: warnAmber, minimumSize: const Size.fromHeight(44)),
            child: const Text('Ndiyo, ni hiyo'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() {
            _differentConfirmed = true;
            _error = null;
          }),
          style: OutlinedButton.styleFrom(
            foregroundColor: warnAmber,
            side: const BorderSide(color: warnAmber, width: 2),
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('Hapana, ni tofauti'),
        ),
      ]),
    );
  }

  Widget _unitsCard() {
    return _card([
      const Text('Inauzwa kwa vipimo gani?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      Text('Hisa inahesabiwa kwa ${unitLabel(_baseUnit)} moja moja', style: const TextStyle(fontSize: 12, color: mutedText)),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(unitLabel(_baseUnit), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('kipimo kidogo kabisa'),
        trailing: TextButton(onPressed: _pickBase, child: const Text('Badilisha')),
      ),
      for (final u in _packs)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(unitLabel(u.name), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('= ${unitLabel(_baseUnit, u.baseQuantity)} ${u.baseQuantity} (gusa kubadilisha)'),
          onTap: () => _changeSize(u),
          trailing: IconButton(
            tooltip: 'Ondoa',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _packs.remove(u);
              _prices.remove(u.baseQuantity); // not disposed here: its field is still on screen until this rebuild
            }),
          ),
        ),
      if (_packs.length < 5)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _addPack, icon: const Icon(Icons.add), label: const Text('Kipimo kingine (kadi, boksi…)')),
        ),
    ]);
  }

  Widget _pricesCard() {
    final units = [DraftUnit(name: _baseUnit, baseQuantity: 1), ..._packs];
    final base = int.tryParse(_priceFor(1).text.trim());
    return _card([
      const Text('Bei ya kuuza', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      for (final u in units)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: _priceFor(u.baseQuantity),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: u.baseQuantity == 1
                  ? '${unitLabel(u.name)} 1 (TSh)'
                  : '${unitLabel(u.name)} (${unitLabel(_baseUnit, u.baseQuantity)} ${u.baseQuantity}) (TSh)',
              // A whole kadi is usually a little cheaper than its tablets one by one.
              helperText: u.baseQuantity > 1 && base != null ? 'Moja moja ingekuwa ${formatTsh(base * u.baseQuantity)}' : null,
            ),
          ),
        ),
      const SizedBox(height: 8),
      const Text('Faida itaonekana ukiweka bei ya kununua, hatua inayofuata.', style: TextStyle(fontSize: 12, color: mutedText)),
    ]);
  }

  Widget _noPriceCard() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(20)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline, color: inkColor),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bei ya kuuza: mwenye duka ataiweka', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Wewe rekodi kilichokuja tu. Bidhaa hii haitauzwa mpaka mzigo uthibitishwe na bei iwekwe.',
                  style: TextStyle(fontSize: 13)),
            ]),
          ),
        ]),
      );

  Widget _reorderCard() {
    final unit = _packs.isEmpty ? _baseUnit : _packs.first.name;
    return _card([
      Row(children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Agiza ikifika', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('Itaonekana kwenye "Chache"', style: TextStyle(fontSize: 12, color: mutedText)),
          ]),
        ),
        IconButton.filledTonal(
          onPressed: _reorderPacks > 0 ? () => setState(() => _reorderPacks--) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 76,
          child: Text('$_reorderPacks ${unitLabel(unit, _reorderPacks)}',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        IconButton.filled(onPressed: () => setState(() => _reorderPacks++), icon: const Icon(Icons.add)),
      ]),
    ]);
  }
}
