import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../purchases/new_product.dart';
import '../purchases/new_product_screen.dart';
import '../../core/i18n.dart';

/// "Ingiza kwa wingi": many lines at once, on a laptop.
///
/// For the two days when typing on a phone hurts most: setup day (everything
/// in the shop, from the owner's notebook) and big deliveries (a 40-line
/// invoice). One row = one batch. Keyboard first: Tab to the next cell,
/// Enter on the last cell starts a new row.
///
/// It saves through the SAME rules as Pokea mzigo (one POST purchases): names
/// from the catalogue, the duplicate check, prices only with edit_prices,
/// four-eyes. "Kagua" runs all of them without saving; every problem comes
/// back with its line, and that row turns red.
class BulkEntryScreen extends StatefulWidget {
  const BulkEntryScreen({super.key, required this.session});

  final Session session;

  @override
  State<BulkEntryScreen> createState() => _BulkEntryScreenState();
}

/// "Hisa ya mwanzo" is not a supplier: the opening stock has no supplier, so
/// Agiza never thinks "the last delivery came from Hisa ya mwanzo".
const _openingLabel = 'Hisa ya mwanzo';

class _BulkEntryScreenState extends State<BulkEntryScreen> {
  bool _opening = true;
  List<Map<String, dynamic>> _suppliers = [];
  int? _supplierId;
  final _invoice = TextEditingController();
  final _invoiceTotal = TextEditingController();
  final List<_Row> _rows = [];
  bool _busy = false;
  String? _banner; // whole-sheet message (top)
  bool _bannerOk = false;
  String _clientUuid = randomId();

  ApiClient get _api => widget.session.api;
  bool get _canPrice => widget.session.user!.can(Perm.editPrices);
  bool get _costs => widget.session.user!.can(Perm.viewCosts);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      _rows.add(_Row());
    }
    _loadSuppliers();
  }

  @override
  void dispose() {
    _invoice.dispose();
    _invoiceTotal.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final d = (await _api.get('suppliers') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _suppliers = d);
    } on ApiException {
      // the opening stock doesn't need them
    }
  }

  // ------------------------------------------------------------- rows

  List<_Row> get _filled => _rows.where((r) => !r.isEmpty).toList();

  void _addRow({bool focus = true}) {
    final r = _Row();
    setState(() => _rows.add(r));
    if (focus) WidgetsBinding.instance.addPostFrameCallback((_) => r.nameFocus.requestFocus());
  }

  void _removeRow(_Row r) {
    setState(() {
      _rows.remove(r);
      if (_rows.isEmpty) _rows.add(_Row());
    });
    r.dispose();
  }

  /// A product picked in the name cell: the usual (biggest) pack is proposed.
  void _setProduct(_Row r, Product p, {NewProductDraft? draft, int? linkId, String? linkVariant}) {
    setState(() {
      r.product = p;
      r.draft = draft;
      r.linkId = linkId;
      r.linkVariant = linkVariant;
      r.name.text = p.name;
      final biggest = p.units.isEmpty ? null : p.units.last;
      r.packName = biggest?.name ?? p.baseUnit;
      r.packSize = biggest?.baseQuantity ?? 1;
      r.serverError = null;
    });
  }

  /// Same new product on two rows (two batches) → one draft, created once.
  List<NewProductDraft> get _drafts {
    final seen = <NewProductDraft>{};
    return [for (final r in _rows) if (r.draft != null && seen.add(r.draft!)) r.draft!];
  }

  Future<void> _pickCatalogue(_Row r, Map<String, dynamic>? item, Map<String, dynamic>? variant, String? typed) async {
    final choice = await Navigator.of(context).push<NewProductChoice>(MaterialPageRoute(
      builder: (_) => NewProductScreen(api: _api, canPrice: _canPrice, item: item, variant: variant, typedName: typed),
    ));
    if (choice == null || !mounted) return;
    if (choice.existing != null) {
      _setProduct(r, choice.existing!, linkId: choice.linkCatalogueItemId, linkVariant: choice.linkVariant);
    } else {
      _setProduct(r, choice.draft!.asProduct(), draft: choice.draft);
    }
  }

  Future<void> _editDraft(_Row r) async {
    final choice = await Navigator.of(context).push<NewProductChoice>(MaterialPageRoute(
      builder: (_) => NewProductScreen(api: _api, canPrice: _canPrice, initial: r.draft),
    ));
    if (choice?.draft != null && mounted) setState(() => r.product = r.draft!.asProduct());
  }

  Future<void> _choosePack(_Row r) async {
    final p = r.product;
    if (p == null) return;
    final base = p.units.first.name;
    final picked = await showDialog<(String, int)>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(tr('Kifungashio cha :name', {'name': p.name})),
        children: [
          for (final u in p.units)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop((u.name, u.baseQuantity)),
              child: Text(u.baseQuantity == 1 ? unitLabel(u.name) : '${unitLabel(u.name)} (${unitLabel(base, u.baseQuantity)} ${u.baseQuantity})'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialog).pop(('', 0)),
            child: const T('Kingine… (mfano boksi ya 50)', style: TextStyle(color: brandGreen, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    var (name, size) = picked;
    if (size == 0) {
      final res = await showDialog<(String, int)>(context: context, builder: (_) => _OtherPackDialog(baseUnit: base));
      if (res == null || !mounted) return;
      (name, size) = res;
    }
    setState(() {
      r.packName = name;
      r.packSize = size;
    });
  }

  // ------------------------------------------------------------- paste

  /// Rows copied from Excel / Google Sheets (cells separated by Tab):
  /// Bidhaa · Kifungashio · Ukubwa · Idadi · Batch · EXP · Bei ya kununua.
  Future<void> _paste() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _PasteDialog());
    if (text == null || text.trim().isEmpty || !mounted) return;
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    setState(() => _rows.removeWhere((r) => r.isEmpty));
    var matched = 0;
    for (final line in lines) {
      final c = line.split('\t').map((x) => x.trim()).toList();
      String at(int i) => i < c.length ? c[i] : '';
      final r = _Row()
        ..name.text = at(0)
        ..packName = normalUnitName(at(1).isEmpty ? '' : at(1))
        ..packSize = int.tryParse(at(2).replaceAll(RegExp(r'[^0-9]'), '')) ?? 1
        ..packs.text = at(3).replaceAll(RegExp(r'[^0-9]'), '')
        ..batch.text = at(4)
        ..exp.text = at(5)
        ..cost.text = at(6).replaceAll(RegExp(r'[^0-9]'), '');
      _rows.add(r);
      // Only an exact name (ignoring capitals) is matched; anything else waits
      // for a person to pick it. Names are never guessed.
      try {
        final found = (await _api.get('products', query: {'q': at(0)}) as List)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .where((p) => !p.suggested && p.name.toLowerCase() == at(0).toLowerCase());
        if (found.isNotEmpty) {
          r.product = found.first;
          if (r.packName.isEmpty) {
            r.packName = found.first.units.last.name;
            r.packSize = found.first.units.last.baseQuantity;
          }
          matched++;
        }
      } on ApiException {
        // left for the person to pick
      }
    }
    if (!mounted) return;
    _rows.add(_Row());
    setState(() {
      _bannerOk = matched == lines.length;
      _banner = tr('Mistari :lines imebandikwa. :a', {'lines': lines.length, 'a': lines.length - matched == 0 ? tr('Bidhaa zote zimetambuliwa.') : tr('Bidhaa :a hazijatambuliwa: zichague (bofya jina).', {'a': lines.length - matched})});
    });
  }

  // ------------------------------------------------------------- order

  Future<void> _fillFromOrder() async {
    try {
      final orders = (await _api.get('purchase-orders') as List)
          .cast<Map<String, dynamic>>()
          .where((o) => (o['supplier'] as Map?)?['id'] == _supplierId)
          .toList();
      if (!mounted) return;
      if (orders.isEmpty) {
        setState(() {
          _banner = tr('Hakuna agizo linalosubiriwa kutoka kwa msambazaji huyu.');
          _bannerOk = false;
        });
        return;
      }
      final o = orders.last; // the oldest open one
      setState(() {
        _rows.removeWhere((r) => r.isEmpty);
        for (final l in ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          final units = [for (final u in ((l['units'] as List?) ?? const []).cast<Map<String, dynamic>>()) ProductUnit.fromJson(u)];
          if (units.isEmpty) continue;
          final p = Product(
            id: asInt(l['product_id']), name: '${l['product']}', baseUnit: units.first.name,
            unitPrice: units.first.price, onHand: 0, lowStock: false, units: units,
          );
          _rows.add(_Row()
            ..product = p
            ..name.text = p.name
            ..packName = '${l['pack_name']}'
            ..packSize = asInt(l['pack_size'])
            ..packs.text = '${l['packs']}');
        }
        _rows.add(_Row());
        _banner = tr('Mistari imejazwa kutoka agizo. Ongeza batch, EXP na bei kutoka ankara.');
        _bannerOk = true;
      });
    } on ApiException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  // ------------------------------------------------------------- check & save

  Map<String, dynamic> _lineJson(_Row r) {
    final (y, m) = r.expiry!;
    return {
      if (r.draft != null) 'new_product': r.draft!.toJson() else 'product_id': r.product!.id,
      if (r.linkId != null) 'link_catalogue_item_id': r.linkId,
      if (r.linkVariant != null) 'link_variant': r.linkVariant,
      'batch_number': r.batch.text.trim(),
      'expiry_month': '$y-${m.toString().padLeft(2, '0')}',
      'pack_name': r.packName,
      'pack_size': r.packSize,
      'packs': int.parse(r.packs.text),
      'pack_cost': int.tryParse(r.cost.text) ?? 0,
    };
  }

  Future<void> _submit({required bool dryRun}) async {
    final rows = _filled;
    setState(() {
      for (final r in rows) {
        r.serverError = null;
      }
      _banner = null;
    });
    if (rows.isEmpty) return;
    if (rows.any((r) => r.problem != null)) {
      setState(() {
        _banner = tr('Rekebisha mistari yenye rangi nyekundu kwanza.');
        _bannerOk = false;
      });
      return;
    }
    // Expired rows are left out: they never become stock (see the note on the row).
    final send = rows.where((r) => !r.isExpired).toList();
    if (send.isEmpty) return;
    setState(() => _busy = true);
    try {
      final body = {
        if (!dryRun) 'client_uuid': _clientUuid,
        if (!_opening && _supplierId != null) 'supplier_id': _supplierId,
        'invoice_number': _opening ? _openingLabel : (_invoice.text.trim().isEmpty ? null : _invoice.text.trim()),
        if (!_opening && int.tryParse(_invoiceTotal.text) != null) 'invoice_total': int.parse(_invoiceTotal.text),
        'lines': [for (final r in send) _lineJson(r)],
      };
      final res = await _api.post(dryRun ? 'purchases?dry_run=1' : 'purchases', body) as Map<String, dynamic>;
      if (!mounted) return;
      if (dryRun) {
        setState(() {
          _bannerOk = true;
          _banner = tr('Kila kitu kiko sawa: mistari :send:a. Bonyeza Hifadhi.', {'send': send.length, 'a': _costs ? ' · ${formatTsh(asInt(res['total_cost']))}' : ''});
        });
      } else {
        final pending = res['status'] == 'pending';
        for (final r in _rows) {
          r.dispose();
        }
        setState(() {
          _rows
            ..clear()
            ..add(_Row());
          _clientUuid = randomId(); // the next sheet is a new delivery
          _invoice.clear();
          _invoiceTotal.clear();
          _bannerOk = true;
          _banner = pending
              ? tr('Imehifadhiwa: mistari :send. Inasubiri kuthibitishwa (Mizigo ya kuthibitisha).', {'send': send.length})
              : tr('Imehifadhiwa: mistari :send imeingia kwenye hisa.', {'send': send.length});
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _bannerOk = false;
        _banner = e.message;
        // Mark the row(s) the server named: "line": 3, or errors under "lines.3.…".
        final line = e.data['line'];
        if (line is int && line < send.length) send[line].serverError = e.message.replaceFirst(RegExp(r'^Mstari \d+: '), '');
        final errors = (e.data['errors'] as Map?) ?? const {};
        for (final entry in errors.entries) {
          final m = RegExp(r'^lines\.(\d+)\.').firstMatch('${entry.key}');
          final i = m == null ? null : int.parse(m.group(1)!);
          if (i != null && i < send.length) send[i].serverError = '${(entry.value as List?)?.first ?? entry.value}';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final rows = _filled;
    final problems = rows.where((r) => r.problem != null).length;
    final warnings = rows.where((r) => r.problem == null && r.warning(_costs) != null).length;
    final total = rows.where((r) => !r.isExpired).fold<int>(0, (t, r) => t + r.lineTotal);
    final drafts = _drafts.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const T('Ingiza kwa wingi', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.keyN, control: true): _NewRowIntent()},
        child: Actions(
          actions: {_NewRowIntent: CallbackAction<_NewRowIntent>(onInvoke: (_) => _addRow())},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: T('Hisa ya mwanzo')),
                    ButtonSegment(value: false, label: T('Mzigo wa msambazaji')),
                  ],
                  selected: {_opening},
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(selectedBackgroundColor: brandGreen, selectedForegroundColor: Colors.white),
                  onSelectionChanged: (v) => setState(() => _opening = v.first),
                ),
                const T('Tab = kisanduku kinachofuata · Enter kwenye bei = mstari mpya · Ctrl+N = mstari mpya',
                    style: TextStyle(fontSize: 12, color: mutedText)),
              ]),
              const SizedBox(height: 12),
              _header(total),
              if (_banner != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bannerOk ? const Color(0xFFDDF3EA) : const Color(0xFFFDE7E4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_banner!, style: TextStyle(fontWeight: FontWeight.w700, color: _bannerOk ? const Color(0xFF145F4B) : dangerRed)),
                ),
              const SizedBox(height: 12),
              _grid(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const T('Mstari mpya')),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const T('Bandika kutoka Excel')),
                Text(
                  tr('Mistari :rows:a:b', {'rows': rows.length, 'a': drafts > 0 ? tr(' · bidhaa mpya :drafts', {'drafts': drafts}) : '', 'b': _costs ? ' · ${formatTsh(total)}' : ''}),
                  style: const TextStyle(color: mutedText),
                ),
                if (problems > 0)
                  Text(tr('Matatizo :problems ya kurekebisha', {'problems': problems}), style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w800)),
                if (problems == 0 && warnings > 0)
                  Text(tr('Onyo :warnings (unaweza kuhifadhi)', {'warnings': warnings}), style: const TextStyle(color: warnAmber, fontWeight: FontWeight.w800)),
                OutlinedButton(
                  onPressed: _busy || rows.isEmpty ? null : () => _submit(dryRun: true),
                  child: const T('Kagua'),
                ),
                FilledButton(
                  onPressed: _busy || rows.isEmpty || problems > 0 ? null : () => _submit(dryRun: false),
                  style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                  child: Text(_busy ? tr('Inatuma…') : tr('Hifadhi mistari :a', {'a': rows.where((r) => !r.isExpired).length})),
                ),
              ]),
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  tr('Hakuna kinachoingia kwenye hisa mpaka ubonyeze Hifadhi. "Kagua" inaangalia kila kitu bila kuhifadhi.'),
                  style: TextStyle(fontSize: 12, color: mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(int total) {
    if (_opening) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: softCard(radius: 16),
        child: Text(
          tr('Hisa ya mwanzo: kila kitu kilichopo dukani siku ya kuanza. Hesabu kutoka kwenye rafu, si kutoka kumbukumbu. Bila msambazaji: Agiza itajifunza msambazaji wa kila bidhaa mzigo wa kwanza ukifika.'),
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    final inv = int.tryParse(_invoiceTotal.text);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: softCard(radius: 16),
      child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(
          width: 240,
          child: InputDecorator(
            decoration: InputDecoration(labelText: tr('Msambazaji')),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _supplierId,
                isDense: true,
                isExpanded: true,
                hint: const T('Chagua'),
                items: [for (final s in _suppliers) DropdownMenuItem(value: asInt(s['id']), child: Text('${s['name']}'))],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
            ),
          ),
        ),
        SizedBox(width: 160, child: TextField(controller: _invoice, decoration: InputDecoration(labelText: tr('Namba ya ankara')))),
        SizedBox(
          width: 160,
          child: TextField(
            controller: _invoiceTotal,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Jumla ya ankara')),
          ),
        ),
        if (inv != null && _costs)
          Text(
            inv == total ? tr('✓ Inalingana na mistari') : tr('Mistari :a · tofauti :b', {'a': formatTsh(total), 'b': formatTsh((inv - total).abs())}),
            style: TextStyle(fontWeight: FontWeight.w800, color: inv == total ? brandGreen : warnAmber),
          ),
        if (_supplierId != null)
          TextButton.icon(onPressed: _fillFromOrder, icon: const Icon(Icons.playlist_add), label: const T('Jaza kutoka agizo')),
      ]),
    );
  }

  static const _widths = <double>[36, 300, 190, 80, 120, 100, 140, 190, 40];

  Widget _grid() {
    const heads = ['#', 'BIDHAA', 'KIFUNGASHIO', 'IDADI', 'BATCH', 'EXP (MM/YYYY)', 'BEI YA KUNUNUA', 'BEI YA KUUZA', ''];
    return Container(
      decoration: softCard(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _widths.reduce((a, b) => a + b) + 16,
          child: FocusTraversalGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                color: mintSoft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(children: [
                  for (var i = 0; i < heads.length; i++)
                    SizedBox(
                      width: _widths[i],
                      child: Text(tr(heads[i]), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: mutedText)),
                    ),
                ]),
              ),
              for (var i = 0; i < _rows.length; i++) _row(i, _rows[i]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(int index, _Row r) {
    final problem = r.problem;
    final warning = problem == null ? r.warning(_costs) : null;
    final bg = r.isExpired
        ? const Color(0xFFF3F3F3)
        : problem != null
            ? const Color(0xFFFDEEEC)
            : warning != null
                ? const Color(0xFFFFF8EA)
                : Colors.white;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        );
    Widget cell(int i, Widget child) => SizedBox(width: _widths[i], child: Padding(padding: const EdgeInsets.only(right: 6), child: child));

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cell(0, Padding(padding: const EdgeInsets.only(top: 12), child: Text('${index + 1}', style: const TextStyle(color: mutedText)))),
          cell(1, _NameCell(
            row: r,
            api: _api,
            drafts: _drafts,
            onProduct: (p) => _setProduct(r, p),
            onDraft: (d) => _setProduct(r, d.asProduct(), draft: d),
            onCatalogue: (item, v) => _pickCatalogue(r, item, v, null),
            onTyped: (t) => _pickCatalogue(r, null, null, t),
            onEditDraft: () => _editDraft(r),
            onClear: () => setState(() {
              r
                ..product = null
                ..draft = null
                ..linkId = null
                ..linkVariant = null
                ..serverError = null;
            }),
          )),
          cell(2, OutlinedButton(
            onPressed: r.product == null ? null : () => _choosePack(r),
            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(r.packLabel, overflow: TextOverflow.ellipsis),
          )),
          cell(3, TextField(
            controller: r.packs,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: dec('0'),
          )),
          cell(4, TextField(controller: r.batch, onChanged: (_) => setState(() {}), decoration: dec('A91'))),
          cell(5, TextField(
            controller: r.exp,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')), LengthLimitingTextInputFormatter(7)],
            onChanged: (_) => setState(() {}),
            decoration: dec('06/2028'),
          )),
          cell(6, TextField(
            controller: r.cost,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            // Enter on the last typed cell: next row.
            onSubmitted: (_) {
              if (identical(r, _rows.last)) {
                _addRow();
              } else {
                _rows[index + 1].nameFocus.requestFocus();
              }
            },
            decoration: dec(tr('kwa :a', {'a': r.packName.isEmpty ? tr('kifungashio') : unitLabel(r.packName)})),
          )),
          cell(7, Padding(
            padding: const EdgeInsets.only(top: 10),
            child: r.draft != null
                ? InkWell(
                    onTap: () => _editDraft(r),
                    child: Text(
                      r.draft!.hasPrices
                          ? r.draft!.units.map((u) => '${unitLabel(u.name)} ${formatTsh(u.price!)}').join(' · ')
                          : tr('Mwenye duka ataweka'),
                      style: const TextStyle(fontSize: 12, color: brandGreen, fontWeight: FontWeight.w700),
                    ),
                  )
                : Text(
                    r.product == null ? '' : r.product!.units.map((u) => '${unitLabel(u.name)} ${formatTsh(u.price)}').join(' · '),
                    style: const TextStyle(fontSize: 12, color: mutedText),
                  ),
          )),
          cell(8, IconButton(
            tooltip: tr('Futa mstari'),
            onPressed: () => _removeRow(r),
            icon: const Icon(Icons.close, size: 18),
          )),
        ]),
        if (!r.isEmpty && (problem ?? warning ?? r.note) != null)
          Padding(
            padding: EdgeInsets.only(left: _widths[0], top: 4),
            child: Text(
              problem ?? warning ?? r.note!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: problem != null ? dangerRed : (warning != null ? warnAmber : mutedText),
              ),
            ),
          ),
      ]),
    );
  }
}

class _NewRowIntent extends Intent {
  const _NewRowIntent();
}

/// One line of the sheet.
class _Row {
  Product? product;
  NewProductDraft? draft;
  int? linkId;
  String? linkVariant;
  String packName = '';
  int packSize = 1;
  final name = TextEditingController();
  final packs = TextEditingController();
  final batch = TextEditingController();
  final exp = TextEditingController();
  final cost = TextEditingController();
  final nameFocus = FocusNode();
  String? serverError;

  void dispose() {
    for (final c in [name, packs, batch, exp, cost]) {
      c.dispose();
    }
    nameFocus.dispose();
  }

  bool get isEmpty =>
      product == null && name.text.trim().isEmpty && packs.text.isEmpty && batch.text.trim().isEmpty && exp.text.isEmpty && cost.text.isEmpty;

  /// "06/2028", "6/28", "06-2028" → (2028, 6).
  (int, int)? get expiry {
    final m = RegExp(r'^(\d{1,2})\s*[/-]\s*(\d{2}|\d{4})$').firstMatch(exp.text.trim());
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    var year = int.parse(m.group(2)!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return (year, month);
  }

  /// A box says "EXP 06/2028": usable to the end of June.
  bool get isExpired {
    final e = expiry;
    if (e == null) return false;
    final now = DateTime.now();
    return e.$1 < now.year || (e.$1 == now.year && e.$2 < now.month);
  }

  int get lineTotal => (int.tryParse(packs.text) ?? 0) * (int.tryParse(cost.text) ?? 0);

  String get packLabel {
    if (product == null) return '—';
    if (packName.isEmpty) return tr('Chagua');
    final base = product!.units.first.name;
    return packSize > 1 ? '${unitLabel(packName)} (${unitLabel(base, packSize)} $packSize)' : unitLabel(packName);
  }

  /// What blocks saving, in plain words.
  String? get problem {
    if (serverError != null) return serverError;
    if (isEmpty) return null;
    if (product == null) return name.text.trim().isEmpty ? tr('Chagua bidhaa') : tr('Chagua ":a" kwenye orodha (bofya jina)', {'a': name.text.trim()});
    if ((int.tryParse(packs.text) ?? 0) < 1) return tr('Andika idadi');
    if (batch.text.trim().isEmpty) return tr('Andika namba ya batch (iko kwenye boksi)');
    if (expiry == null) return tr('EXP iandikwe kama 06/2028');
    if (cost.text.isEmpty) return tr('Andika bei ya kununua kwa :a', {'a': unitLabel(packName)});
    return null;
  }

  /// Saved anyway, but worth a look.
  String? warning(bool costs) {
    if (isExpired) return tr('Imeisha muda: mstari huu hautaingizwa kwenye hisa. Iondoe kwenye rafu.');
    final e = expiry;
    if (e != null) {
      final now = DateTime.now();
      final months = (e.$1 - now.year) * 12 + e.$2 - now.month;
      if (months < 2) return tr('Inaisha karibuni (:a/:b): iuze kwanza', {'a': e.$2, 'b': e.$1});
    }
    final c = int.tryParse(cost.text);
    if (costs && c != null && product != null && packSize > 0) {
      final perBase = c / packSize;
      final p = draft != null ? (draft!.units.first.price ?? 0) : product!.units.first.price;
      if (p > 0 && p < perBase) return tr('Unauza :a :b, unanunua :c', {'a': unitLabel(product!.units.first.name), 'b': formatTsh(p), 'c': formatTsh(perBase.round())});
    }
    return null;
  }

  /// Neutral information.
  String? get note => draft != null
      ? (draft!.offCatalogue ? tr('Bidhaa mpya · nje ya katalogi') : tr('Bidhaa mpya · kutoka katalogi'))
      : (linkId != null ? tr('Jina la katalogi litaunganishwa na bidhaa hii') : null);
}

/// The name cell: type, then pick from your products, this sheet's new
/// products, or the catalogue (+ Mpya). Nothing is ever guessed.
class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.row,
    required this.api,
    required this.drafts,
    required this.onProduct,
    required this.onDraft,
    required this.onCatalogue,
    required this.onTyped,
    required this.onEditDraft,
    required this.onClear,
  });

  final _Row row;
  final ApiClient api;
  final List<NewProductDraft> drafts;
  final void Function(Product) onProduct;
  final void Function(NewProductDraft) onDraft;
  final void Function(Map<String, dynamic>, Map<String, dynamic>) onCatalogue;
  final void Function(String) onTyped;
  final VoidCallback onEditDraft;
  final VoidCallback onClear;

  static final Map<String, List<_Option>> _cache = {};

  Future<List<_Option>> _options(String q) async {
    q = q.trim();
    if (q.length < 2) return const [];
    final key = q.toLowerCase();
    final cached = _cache[key];
    if (cached != null) return [for (final d in drafts) if (d.name.toLowerCase().contains(key)) _Option.draft(d), ...cached];
    final out = <_Option>[];
    try {
      final products = await api.get('products', query: {'q': q}) as List;
      for (final p in products.cast<Map<String, dynamic>>().take(6)) {
        out.add(_Option.product(Product.fromJson(p)));
      }
      final cat = await api.get('catalogue', query: {'q': q}) as Map<String, dynamic>;
      for (final item in ((cat['results'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        for (final v in ((item['variants'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          if (v['own_product_id'] == null && out.length < 14) out.add(_Option.catalogue(item, v));
        }
      }
    } on ApiException {
      // offline: only what's typed
    }
    out.add(_Option.typed(q));
    _cache[key] = out;
    return [for (final d in drafts) if (d.name.toLowerCase().contains(key)) _Option.draft(d), ...out];
  }

  @override
  Widget build(BuildContext context) {
    if (row.product != null) {
      return Row(children: [
        Expanded(
          child: InkWell(
            onTap: row.draft != null ? onEditDraft : null,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(row.product!.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        IconButton(
          tooltip: tr('Badilisha bidhaa'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          // Back to typing, keeping the name.
          onPressed: onClear,
        ),
      ]);
    }
    return RawAutocomplete<_Option>(
      textEditingController: row.name,
      focusNode: row.nameFocus,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (v) => _options(v.text),
      onSelected: (o) {
        switch (o.kind) {
          case _Kind.product:
            onProduct(o.product!);
          case _Kind.draft:
            onDraft(o.draft!);
          case _Kind.catalogue:
            onCatalogue(o.item!, o.variant!);
          case _Kind.typed:
            onTyped(o.label);
        }
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          hintText: tr('Andika jina…'),
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
      ),
      optionsViewBuilder: (context, onSelect, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), shrinkWrap: true, children: [
              for (final o in options)
                ListTile(
                  dense: true,
                  title: Text(o.kind == _Kind.typed ? tr('Ongeza ":label" kama bidhaa mpya', {'label': o.label}) : o.label,
                      style: TextStyle(fontWeight: FontWeight.w700, color: o.kind == _Kind.typed ? brandGreen : null)),
                  subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                  trailing: switch (o.kind) {
                    _Kind.catalogue => const T('+ Mpya', style: TextStyle(color: brandGreen, fontWeight: FontWeight.w800)),
                    _Kind.draft => const T('mpya', style: TextStyle(color: brandGreen, fontWeight: FontWeight.w800)),
                    _ => null,
                  },
                  onTap: () => onSelect(o),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

enum _Kind { product, draft, catalogue, typed }

class _Option {
  _Option.product(Product this.product)
      : kind = _Kind.product,
        draft = null,
        item = null,
        variant = null,
        label = product.name,
        subtitle = tr('Bidhaa zako · zipo :a', {'a': describeStock(product.onHand, product.units)});
  _Option.draft(NewProductDraft this.draft)
      : kind = _Kind.draft,
        product = null,
        item = null,
        variant = null,
        label = draft.name,
        subtitle = tr('Mpya kwenye karatasi hii');
  _Option.catalogue(Map<String, dynamic> this.item, Map<String, dynamic> this.variant)
      : kind = _Kind.catalogue,
        product = null,
        draft = null,
        label = '${variant['name']}',
        subtitle = tr('Katalogi (:a)', {'a': '${item['source']}'.toUpperCase()});
  _Option.typed(String text)
      : kind = _Kind.typed,
        product = null,
        draft = null,
        item = null,
        variant = null,
        label = text,
        subtitle = tr('Nje ya katalogi');

  final _Kind kind;
  final Product? product;
  final NewProductDraft? draft;
  final Map<String, dynamic>? item;
  final Map<String, dynamic>? variant;
  final String label;
  final String? subtitle;
}

/// A packaging the product never had: its name and size.
class _OtherPackDialog extends StatefulWidget {
  const _OtherPackDialog({required this.baseUnit});

  final String baseUnit;

  @override
  State<_OtherPackDialog> createState() => _OtherPackDialogState();
}

class _OtherPackDialogState extends State<_OtherPackDialog> {
  String? _name;
  final _size = TextEditingController();

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = int.tryParse(_size.text) ?? 0;
    return AlertDialog(
      title: const T('Kifungashio kingine'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        InputDecorator(
          decoration: InputDecoration(labelText: tr('Jina')),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _name,
              isDense: true,
              isExpanded: true,
              items: [for (final (id, label) in standardUnits) DropdownMenuItem(value: id, child: Text(label))],
              onChanged: (v) => setState(() => _name = v),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _size,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Ina :a ngapi?', {'a': unitLabel(widget.baseUnit, 2)})),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi')),
        FilledButton(
          onPressed: _name == null || size < 1 ? null : () => Navigator.of(context).pop((_name!, size)),
          child: const T('Weka'),
        ),
      ],
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const T('Bandika kutoka Excel'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('Nakili mistari kwenye Excel au Google Sheets (bila kichwa), kisha bandika hapa (Ctrl+V).\nMpangilio wa safu: Bidhaa · Kifungashio · Ukubwa · Idadi · Batch · EXP · Bei ya kununua'),
            style: TextStyle(fontSize: 12, color: mutedText),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _c,
            autofocus: true,
            maxLines: 10,
            decoration: InputDecoration(border: OutlineInputBorder(), hintText: 'Paracetamol 500mg\tboksi\t100\t5\tP131\t06/2028\t2000'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_c.text), child: const T('Bandika')),
      ],
    );
  }
}
