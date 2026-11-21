import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../purchases/receive_line.dart';
import '../purchases/receive_screen.dart';

/// Orodha ya kununua (v0.48): the buying trip. Tick what was bought and what
/// it cost (beside the last price); "Haikupatikana" keeps it for next time.
/// The bought part then becomes a delivery: Pokea opens with it filled in,
/// and only the batch and EXP are read off each box.
///
/// Without [listId]: the open lists, to pick one.
class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key, required this.session, this.listId});

  final Session session;
  final int? listId;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  Map<String, dynamic>? _list;
  List<Map<String, dynamic>>? _lists;
  String? _error;
  final Set<int> _busy = {};

  ApiClient get _api => widget.session.api;
  bool get _costs => widget.session.user!.can(Perm.viewCosts);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.listId != null) {
        final l = await _api.get('shopping-lists/${widget.listId}') as Map<String, dynamic>;
        if (mounted) setState(() => (_list = l, _error = null));
      } else {
        final r = await _api.get('shopping-lists') as Map<String, dynamic>;
        if (mounted) setState(() => (_lists = ((r['lists'] as List?) ?? const []).cast<Map<String, dynamic>>(), _error = null));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? tr('Orodha hii haipo tena.') : e.message);
    }
  }

  List<Map<String, dynamic>> get _items => ((_list?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _patch(Map<String, dynamic> i, Map<String, dynamic> body) async {
    final id = asInt(i['id']);
    setState(() => _busy.add(id));
    try {
      final l = await _api.patch('shopping-lists/${_list!['id']}/items/$id', body) as Map<String, dynamic>;
      if (mounted) setState(() => _list = l);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _price(Map<String, dynamic> i) async {
    final last = i['expected_pack_cost'];
    final c = TextEditingController(text: i['paid_pack_cost'] == null ? (last == null ? '' : groupDigits(asInt(last))) : groupDigits(asInt(i['paid_pack_cost'])));
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Bei ya :a moja', {'a': unitLabel('${i['pack_name']}')})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (last != null) Text(tr('Mara ya mwisho: :a', {'a': formatTsh(asInt(last))}), style: const TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInput()],
            decoration: InputDecoration(labelText: tr('Bei uliyolipa (TSh)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(d).pop(moneyValue(c.text)), child: const T('Hifadhi')),
        ],
      ),
    );
    if (v != null && mounted) await _patch(i, {'paid_pack_cost': v, if (i['state'] != 'bought') 'state': 'bought'});
  }

  /// The bought part becomes a delivery; what's left stays for the next trip.
  Future<void> _receive() async {
    final bought = _items.where((i) => i['state'] == 'bought' && i['product'] != null).toList();
    if (bought.isEmpty) return;
    final suppliers = {for (final i in bought) i['supplier_id']};
    final lines = [
      for (final i in bought)
        ReceiveLine(
          chosenProduct: Product.fromJson((i['product'] as Map).cast<String, dynamic>()),
          packName: '${i['pack_name']}',
          packSize: asInt(i['pack_size']) < 1 ? 1 : asInt(i['pack_size']),
          packs: asInt(i['bought_packs'] ?? i['packs']),
          packCost: asInt(i['paid_pack_cost'] ?? i['expected_pack_cost']),
          batch: '',
          expiryYear: 0,
          expiryMonth: 0,
        ),
    ];
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReceiveScreen(
        session: widget.session,
        supplierId: suppliers.length == 1 && suppliers.first != null ? asInt(suppliers.first) : null,
        initialLines: lines,
      ),
    ));
    if (saved != true || !mounted) return;
    try {
      final r = await _api.post('shopping-lists/${_list!['id']}/received', {'item_ids': [for (final i in bought) i['id']]}) as Map<String, dynamic>;
      if (!mounted) return;
      if (r['done'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Orodha imekamilika.'))));
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Zilizobaki :n ziko kwenye orodha kwa safari ijayo.', {'n': r['left']}))));
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The list as plain text, for a rep or whoever goes to buy.
  void _share() {
    final rows = [
      for (final (n, i) in _items.indexed) '${n + 1}. ${i['name']}: ${unitLabel('${i['pack_name']}')} ${i['packs']}',
    ];
    final text = '${tr('Orodha ya kununua')}\n\n${rows.join('\n')}';
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: tr('Futa orodha hii?'), message: tr('Hisa haibadiliki.'), confirm: tr('Futa'), danger: true);
    if (ok != true || !mounted) return;
    try {
      await _api.delete('shopping-lists/${_list!['id']}');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listId == null) return _picker();
    final l = _list;
    final counts = ((l?['counts'] as Map?) ?? const {}).cast<String, dynamic>();
    final bought = asInt(counts['bought']);
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const T('Orodha ya kununua', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (l != null) IconButton(tooltip: tr('Shiriki'), onPressed: _share, icon: const Icon(Icons.share_outlined)),
          if (l != null)
            PopupMenuButton<String>(
              onSelected: (_) => _delete(),
              itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: T('Futa orodha', style: TextStyle(color: dangerRed)))],
            ),
        ],
      ),
      bottomNavigationBar: l == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton.icon(
                  onPressed: bought == 0 ? null : _receive,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(bought == 0 ? tr('Weka alama kwa ulizonunua') : tr('Weka kama mzigo · :n', {'n': bought})),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
            ),
      body: l == null
          ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)) : const AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                _hero(l, counts),
                const SizedBox(height: 12),
                for (final i in _items) _item(i),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: T('Gusa duara ukinunua. Gusa bei kuweka uliyolipa. Haikupatikana inabaki kwa safari ijayo.',
                      style: TextStyle(fontSize: 12, color: mutedText)),
                ),
              ]),
            ),
    );
  }

  Widget _hero(Map<String, dynamic> l, Map<String, dynamic> counts) {
    final planned = l['planned'];
    final paid = asInt(l['paid']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Zimenunuliwa :a kati ya :b', {'a': counts['bought'] ?? 0, 'b': counts['all'] ?? 0}),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatTsh(paid), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            if (_costs && planned != null)
              Text(tr('Makadirio ya orodha yote: :a', {'a': formatTsh(asInt(planned))}), style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        if (asInt(counts['missing']) > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99)),
            child: Text(tr('Hazikupatikana :n', {'n': counts['missing']}), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  Widget _item(Map<String, dynamic> i) {
    final state = '${i['state']}';
    final done = state == 'bought';
    final missing = state == 'missing';
    final busy = _busy.contains(asInt(i['id']));
    final last = i['expected_pack_cost'] == null ? null : asInt(i['expected_pack_cost']);
    final paid = i['paid_pack_cost'] == null ? null : asInt(i['paid_pack_cost']);
    final packs = asInt(i['bought_packs'] ?? i['packs']);
    // Paid more or less than last time, in words people check at the counter.
    String? diff;
    Color diffColor = mutedText;
    if (paid != null && last != null && last > 0 && paid != last) {
      final pct = ((paid - last) * 100 / last).round();
      diff = pct > 0 ? '+$pct%' : '$pct%';
      diffColor = pct > 0 ? warnAmber : brandGreen;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: missing ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          IconButton(
            tooltip: done ? tr('Bado') : tr('Nimenunua'),
            onPressed: busy ? null : () {
              tick();
              _patch(i, {'state': done ? 'todo' : 'bought'});
            },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(done), color: done ? brandGreen : const Color(0xFFB7C6C0), size: 28),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, decoration: missing ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${unitLabel('${i['pack_name']}')} $packs${i['supplier'] == null ? '' : ' · ${i['supplier']}'}',
                    style: const TextStyle(fontSize: 12, color: mutedText)),
                if (missing)
                  const T('Haikupatikana', style: TextStyle(fontSize: 12, color: warnAmber, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          Pressable(
            onTap: busy || missing ? null : () => _price(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(paid != null ? groupDigits(paid) : (last != null ? groupDigits(last) : tr('Bei?')),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: paid != null ? inkColor : mutedText)),
                Text(diff ?? (paid == null ? (last == null ? tr('weka') : tr('mwisho')) : tr('uliyolipa')),
                    style: TextStyle(fontSize: 10.5, color: diffColor, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (v) async {
              if (v == 'missing') return _patch(i, {'state': missing ? 'todo' : 'missing'});
              final n = await askText(context, title: tr('Umenunua ngapi?'), label: unitLabel('${i['pack_name']}'), digitsOnly: true, required: true, initial: '$packs');
              final k = int.tryParse(n ?? '') ?? 0;
              if (k > 0 && mounted) await _patch(i, {'bought_packs': k, 'state': 'bought'});
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'count', child: T('Idadi niliyonunua')),
              PopupMenuItem(value: 'missing', child: T(missing ? 'Imepatikana' : 'Haikupatikana')),
            ],
          ),
        ]),
      ),
    );
  }

  /// The open trips, newest first.
  Widget _picker() {
    final lists = _lists;
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Orodha za kununua', style: TextStyle(fontWeight: FontWeight.w800))),
      body: lists == null
          ? Center(child: _error != null ? Text(_error!) : const AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: T('Hakuna orodha. Kwenye Agiza, chagua bidhaa kisha gusa "Kununua".', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
                  ),
                for (final l in lists)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressable(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListScreen(session: widget.session, listId: asInt(l['id']))));
                        if (mounted) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                        child: Row(children: [
                          const CircleAvatar(backgroundColor: primarySoft, child: Icon(Icons.shopping_bag_outlined, color: brandGreen)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l['title'] ?? tr('Orodha ya kununua')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                [
                                  tr('bidhaa :n', {'n': (l['counts'] as Map?)?['all'] ?? 0}),
                                  tr('zimenunuliwa :n', {'n': (l['counts'] as Map?)?['bought'] ?? 0}),
                                  if (DateTime.tryParse('${l['created_at']}') != null) timeAgo(DateTime.parse('${l['created_at']}')),
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12, color: mutedText),
                              ),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, color: mutedText),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
    );
  }
}
