import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../purchases/receive_screen.dart';
import 'product_stock_screen.dart';

/// "Hisa": every product, what's on the shelf and what it's worth.
///
/// One request (GET stock) brings all ~200 products; search and the filter
/// chips then work on the phone, instantly, without asking the server again.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.session, this.initialFilter = 'zote'});

  final Session session;

  /// zote | chache | hazipo | muda
  final String initialFilter;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Map<String, dynamic>? _data;
  late String _filter = widget.initialFilter;
  String _query = '';
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  // The search box sits under the big green card. When it's tapped, scroll it
  // to the top so the keyboard doesn't hide the results.
  final _searchKey = GlobalKey();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _searchToTop() {
    // Wait for the keyboard to finish opening (the screen shrinks), then scroll.
    Future.delayed(const Duration(milliseconds: 300), () {
      final ctx = _searchKey.currentContext;
      // After a wait, check the context we're about to use is still on screen.
      if (ctx == null || !ctx.mounted || !_searchFocus.hasFocus) return;
      Scrollable.ensureVisible(ctx, alignment: 0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _searchFocus.addListener(() {
      setState(() {}); // the bottom space below depends on focus
      if (_searchFocus.hasFocus) _searchToTop();
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('stock') as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _rows {
    final all = (((_data ?? const {})['products'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final q = _query.trim().toLowerCase();
    final rows = all.where((p) {
      if (q.isNotEmpty && !'${p['name']}'.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        // "Chache" = needs ordering: out of stock first, then running low.
        'chache' => p['is_out'] == true || p['is_low'] == true,
        'hazipo' => p['is_out'] == true,
        'muda' => p['is_expiring'] == true,
        _ => true,
      };
    }).toList();
    if (_filter == 'chache') {
      rows.sort((a, b) => asInt(a['on_hand']).compareTo(asInt(b['on_hand'])));
    }
    return rows;
  }

  Future<void> _openProduct(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductStockScreen(session: widget.session, productId: asInt(p['id']), name: '${p['name']}'),
    ));
    if (mounted) _load(); // price, units or stock may have changed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hisa'), backgroundColor: pageBackground),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => ReceiveScreen(session: widget.session)),
          );
          if (saved == true && mounted) _load();
        },
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('Pokea mzigo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                // Scrolling the list closes the keyboard, like most apps.
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                // While searching, room at the bottom so even 1 result can be
                // scrolled up under the search box.
                padding: EdgeInsets.fromLTRB(20, 4, 20, _searchFocus.hasFocus ? MediaQuery.of(context).size.height * 0.6 : 96),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Expanded(child: Text(_error!, style: const TextStyle(color: dangerRed))),
                        TextButton(onPressed: _load, child: const Text('Jaribu tena')),
                      ]),
                    ),
                  if (_data != null) _summary(),
                  const SizedBox(height: 14),
                  // The key is on this padding, not the TextField: scrolling to it
                  // leaves 12px above the box for the floating "Tafuta dawa" label,
                  // which sits half above the box's top edge and was being cut off.
                  Padding(
                    key: _searchKey,
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onChanged: (v) {
                          setState(() => _query = v);
                          // Fewer results = shorter list: keep the box at the top.
                          _searchToTop();
                        },
                        decoration: const InputDecoration(labelText: 'Tafuta dawa', prefixIcon: Icon(Icons.search)),
                      ),
                  ),
                  const SizedBox(height: 12),
                  _chips(),
                  const SizedBox(height: 12),
                  _list(),
                ],
              ),
            ),
    );
  }

  /// The green card follows the chips: Zote = all stock, Chache = what needs
  /// ordering, Muda = money at risk. The three counts below stay shop-wide.
  Widget _summary() {
    final s = (_data!['summary'] as Map?) ?? const {};
    final rows = _rows;
    final (String title, int value) = switch (_filter) {
      'chache' => ('Za kuagiza · bidhaa ${rows.length} (thamani iliyobaki)', _sum(rows, 'value_at_cost')),
      'hazipo' => ('Hazipo kabisa · bidhaa ${rows.length}', 0),
      'muda' => ('Hatarini: inaisha ndani ya siku 30 · bidhaa ${rows.length}', _sum(rows, 'expiring_value')),
      _ => ('Thamani ya hisa (bei ya kununua)', _sum(rows, 'value_at_cost')),
    };
    final hazipo = _filter == 'hazipo';

    Widget stat(String value, String label, String filter) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _filter = filter),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _filter == filter ? Colors.white.withAlpha(60) : const Color(0xFF23906F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(label, style: const TextStyle(color: Color(0xFFD6F1E7), fontSize: 11)),
              ]),
            ),
          ),
        );

    final lost = asInt(s['expired_value']);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFFD6F1E7), fontSize: 13)),
              Text(hazipo ? '${rows.length}' : formatTsh(value),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                stat('${asInt(s['products'])}', 'bidhaa zote', 'zote'),
                const SizedBox(width: 8),
                stat('${asInt(s['to_reorder'])}', 'za kuagiza', 'chache'),
                const SizedBox(width: 8),
                stat('${asInt(s['expiring'])}', 'muda karibu', 'muda'),
              ]),
            ],
          ),
        ),
        // Expired stock is not "stock": it can't be sold. Its cost is a loss,
        // shown in red so it's never hidden inside the total above.
        if (lost > 0) ...[
          const SizedBox(height: 10),
          Material(
            color: const Color(0xFFFDE7E4),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _filter = 'muda'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: dangerRed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Hasara: ${formatTsh(lost)}',
                          style: const TextStyle(color: dangerRed, fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('Bidhaa ${asInt(s['expired_products'])} zimeisha muda bado ziko kwenye hisa. Ziondoe kwenye rafu.',
                          style: const TextStyle(color: Color(0xFF8F1D14), fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: dangerRed),
                ]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  int _sum(List<Map<String, dynamic>> rows, String key) => rows.fold(0, (t, r) => t + asInt(r[key]));

  Widget _chips() {
    const defs = [('zote', 'Zote'), ('chache', 'Chache'), ('hazipo', 'Hazipo'), ('muda', 'Muda')];
    return Wrap(
      spacing: 8,
      children: [
        for (final (id, label) in defs)
          ChoiceChip(
            label: Text(label),
            selected: _filter == id,
            showCheckmark: false,
            selectedColor: brandGreen,
            labelStyle: TextStyle(color: _filter == id ? Colors.white : inkColor, fontWeight: FontWeight.w700),
            onSelected: (_) => setState(() => _filter = id),
          ),
      ],
    );
  }

  Widget _list() {
    final rows = _rows;
    if (rows.isEmpty) {
      final q = _query.trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          q.isEmpty ? 'Hakuna bidhaa hapa.' : 'Hakuna "$q"${_filter == 'zote' ? '' : ' kwenye kundi hili'}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: mutedText),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: softCard(radius: 22),
      child: Column(
        children: [for (var i = 0; i < rows.length; i++) _row(rows[i], last: i == rows.length - 1)],
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, {required bool last}) {
    final units = ((p['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList();
    final onHand = asInt(p['on_hand']);
    final out = p['is_out'] == true;
    final low = p['is_low'] == true;
    final expiring = p['is_expiring'] == true;
    final expiredQty = asInt(p['expired_quantity']);
    final next = parseDate(p['next_expiry']);

    final (Color dot, String note, Color noteColor) = out
        ? (dangerRed, 'Hazipo · kiwango ${describeStock(asInt(p['reorder_level']), units)}', dangerRed)
        : expiredQty > 0
            ? (dangerRed, '${describeStock(expiredQty, units)} zimeisha muda (hazijauzwa)', dangerRed)
            : expiring && next != null
                ? (const Color(0xFFD0533C), 'Inaisha ${next.day}/${next.month}/${next.year}', dangerRed)
                : low
                    ? (const Color(0xFFC98A00), 'Chache · kiwango ${describeStock(asInt(p['reorder_level']), units)}', warnAmber)
                    : (mintAccent, units.length > 1 ? _unitsNote(units) : unitLabel(units.isEmpty ? '' : units.first.name), mutedText);

    return InkWell(
      onTap: () => _openProduct(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: noteColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(describeStock(onHand, units), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text(formatTsh(asInt(p['value_at_cost'])), style: const TextStyle(fontSize: 11, color: mutedText)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Kadi = vidonge 10" for the first pack, so the size is visible at a glance.
  String _unitsNote(List<ProductUnit> units) {
    final pack = units.firstWhere((u) => u.baseQuantity > 1, orElse: () => units.first);
    return '${unitLabel(pack.name)} = ${unitLabel(units.first.name, pack.baseQuantity)} ${pack.baseQuantity}';
  }
}
