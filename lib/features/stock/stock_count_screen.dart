import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/scan_once.dart';
import '../../core/session.dart';

/// Hesabu ya hisa (stock-take) on the phone: the natural place to do it,
/// walking the shelves with the phone in hand.
///
/// Same rules as the web (server: StockCountService):
///  * count_stock counts; adjust_stock approves (the owner has both);
///  * selling goes on: each product is compared with the system at the moment
///    it is counted;
///  * the count is blind: the system's number shows only after saving;
///  * nothing changes stock until it is approved.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  ApiClient get _api => widget.session.api;
  bool _can(String p) => widget.session.user!.can(p);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _count; // the open count, or null
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _categories = const [];
  final Map<int, int> _diff = {}; // product id → difference (counted products only)
  String _filter = 'all'; // all | todo | diff
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final cur = await _api.get('stock-counts/current') as Map<String, dynamic>;
      final count = cur['count'] as Map<String, dynamic>?;
      if (count != null) {
        final list = await _api.get('stock-counts/${count['id']}/products') as Map<String, dynamic>;
        _products = ((list['products'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _categories = ((list['categories'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _diff
          ..clear()
          ..addAll({
            for (final e in ((list['lines'] is Map ? list['lines'] as Map : const {})).entries) int.parse('${e.key}'): asInt(e.value),
          });
      }
      if (mounted) setState(() => _count = count);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final note = await askText(
      context,
      title: tr('Anza hesabu ya hisa'),
      message: tr('Pita rafu moja moja: gusa bidhaa (au skani barcode yake), andika ulichohesabu rafuni na stoo. Mauzo yanaendelea. Unaweza kuhesabu sehemu tu; zisizohesabiwa hazibadiliki. Tofauti zinabadilisha hisa baada ya idhini.'),
      label: tr('Maelezo (si lazima)'),
      hint: tr('mf. Hesabu ya mwisho wa mwezi'),
      confirm: tr('Anza'),
    );
    if (note == null || !mounted) return;
    try {
      await _api.post('stock-counts', {'note': note.isEmpty ? null : note});
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _products.where((p) {
      if (q.isNotEmpty && !'${p['name']}'.toLowerCase().contains(q)) return false;
      final id = asInt(p['id']);
      return switch (_filter) {
        'todo' => !_diff.containsKey(id),
        'diff' => _diff.containsKey(id) && _diff[id] != 0,
        _ => true,
      };
    }).toList();
  }

  /// Open one product; keep going to the next uncounted one while the person says so.
  Future<void> _countFrom(Map<String, dynamic> product) async {
    var current = product;
    while (mounted) {
      final result = await showModalBottomSheet<_SheetResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: cardColor,
        builder: (_) => _CountSheet(api: _api, countId: asInt(_count!['id']), product: current),
      );
      if (result == null) return;
      if (result.difference != null) setState(() => _diff[asInt(current['id'])] = result.difference!);
      if (!result.next) return;
      final list = _visible;
      final at = list.indexWhere((p) => asInt(p['id']) == asInt(current['id']));
      final rest = [...list.skip(at + 1), ...list.take(at + 1)];
      final next = rest.where((p) => !_diff.containsKey(asInt(p['id']))).firstOrNull;
      if (next == null) {
        _snack(tr('Umehesabu bidhaa zote zinazoonekana. Bonyeza "Maliza na tuma".'));
        return;
      }
      current = next;
    }
  }

  Future<void> _scan() async {
    final code = await scanOnce(context, title: tr('Skani bidhaa unayohesabu'));
    if (code == null || !mounted) return;
    try {
      final p = await _api.get('products/barcode/${Uri.encodeComponent(code)}') as Map<String, dynamic>;
      final found = _products.where((x) => asInt(x['id']) == asInt(p['id'])).firstOrNull ?? {'id': p['id'], 'name': p['name'], 'form': p['form']};
      if (mounted) _countFrom(found);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _submit() async {
    final done = _diff.length;
    final diffs = _diff.values.where((d) => d != 0).length;
    final ok = await confirmDialog(
      context,
      title: tr('Maliza hesabu na tuma'),
      message: tr('Umehesabu :d kati ya :n. Zisizohesabiwa hazitabadilishwa. Tofauti :x zitasubiri idhini ya mwenye ruhusa ya kurekebisha hisa.',
          {'d': done, 'n': _products.length, 'x': diffs}),
      confirm: tr('Tuma'),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.post('stock-counts/${_count!['id']}/submit');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockCountReviewScreen(session: widget.session, countId: asInt(_count!['id']))));
      if (mounted) _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: tr('Sitisha hesabu?'),
      message: tr('Hesabu hii itafungwa bila kubadilisha hisa. Ulichohesabu kitabaki kwenye historia.'),
      confirm: tr('Sitisha'),
      danger: true,
    );
    if (ok != true || !mounted) return;
    try {
      await _api.post('stock-counts/${_count!['id']}/cancel');
      _snack(tr('Hesabu imesitishwa.'));
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counting = _count?['status'] == 'counting';
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: const T('Hesabu ya hisa'),
        backgroundColor: pageBackground,
        actions: [
          IconButton(
            tooltip: tr('Historia ya hesabu'),
            icon: const Icon(Icons.history_rounded),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockCountHistoryScreen(session: widget.session)));
              if (mounted) _load();
            },
          ),
          if (counting && (asInt(_count!['started_by_id']) == widget.session.user!.id || _can(Perm.adjustStock)))
            PopupMenuButton<String>(
              onSelected: (_) => _cancel(),
              itemBuilder: (_) => [PopupMenuItem(value: 'cancel', child: Text(tr('Sitisha hesabu')))],
            ),
        ],
      ),
      floatingActionButton: counting && _can(Perm.countStock)
          ? FloatingActionButton.extended(
              onPressed: _scan,
              backgroundColor: brandGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const T('Skani'),
            )
          : null,
      bottomNavigationBar: counting && _can(Perm.countStock)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: _diff.isEmpty ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.send_rounded),
                  label: const T('Maliza na tuma'),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: AfyaLoader())
          : RefreshIndicator(onRefresh: _load, child: _body(counting)),
    );
  }

  Widget _body(bool counting) {
    if (_error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(_error!, style: const TextStyle(color: dangerRed)),
        TextButton(onPressed: _load, child: const T('Jaribu tena')),
      ]);
    }
    if (_count == null) return _emptyState();
    if (!counting) return _waiting();

    final rows = _visible;
    final done = _diff.length;
    final diffs = _diff.values.where((d) => d != 0).length;
    final total = _products.length;
    // Group by aisle (category), in the shop's order; products without one last.
    final order = {for (var i = 0; i < _categories.length; i++) asInt(_categories[i]['id']): i};
    final names = {for (final c in _categories) asInt(c['id']): '${c['name']}'};
    final groups = <int, List<Map<String, dynamic>>>{};
    for (final p in rows) {
      groups.putIfAbsent(p['category_id'] == null ? 0 : asInt(p['category_id']), () => []).add(p);
    }
    final keys = groups.keys.toList()..sort((a, b) => (order[a] ?? 9999).compareTo(order[b] ?? 9999));

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        _progressCard(done, total, diffs),
        const SizedBox(height: 14),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(labelText: tr('Tafuta bidhaa'), prefixIcon: const Icon(Icons.search)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          _chip('all', tr('Zote')),
          _chip('todo', tr('Bado (:n)', {'n': total - done})),
          _chip('diff', tr('Zenye tofauti (:n)', {'n': diffs})),
        ]),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: T('Hakuna bidhaa hapa.', style: const TextStyle(color: mutedText)))),
        for (final k in keys) ...[
          _aisleHeader(k == 0 ? tr('Bila aina') : (names[k] ?? tr('Aina nyingine')), groups[k]!),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (var i = 0; i < groups[k]!.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 60),
                _productTile(groups[k]![i]),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  Widget _progressCard(int done, int total, int diffs) {
    final pct = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: infoSoft, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr('Hesabu ya hisa #:n inaendelea', {'n': _count!['id']}), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: infoBlue, fontSize: 18)),
        ]),
        const SizedBox(height: 2),
        Text(tr('imeanzishwa na :who', {'who': _count!['started_by'] ?? '—'}), style: const TextStyle(color: mutedText, fontSize: 12)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 500),
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: Colors.white, color: infoBlue),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr(':d / :n zimehesabiwa', {'d': done, 'n': total}) + (diffs > 0 ? ' · ${tr('tofauti :x', {'x': diffs})}' : ''),
            style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _chip(String key, String label) => ChoiceChip(
        label: Text(label),
        selected: _filter == key,
        onSelected: (_) => setState(() => _filter = key),
        selectedColor: primarySoft,
      );

  Widget _aisleHeader(String name, List<Map<String, dynamic>> items) {
    final d = items.where((p) => _diff.containsKey(asInt(p['id']))).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        const Icon(Icons.shelves, size: 18, color: mutedText),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('$d / ${items.length}', style: TextStyle(color: d == items.length ? brandGreen : infoBlue, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }

  Widget _productTile(Map<String, dynamic> p) {
    final id = asInt(p['id']);
    final d = _diff[id];
    return ListTile(
      onTap: _can(Perm.countStock) ? () => _countFrom(p) : null,
      leading: _PackIcon(form: '${p['form'] ?? ''}', faded: d != null),
      title: Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: _StatusBadge(difference: d),
    );
  }

  Widget _emptyState() {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 24), children: [
      const Icon(Icons.fact_check_outlined, size: 64, color: brandGreen),
      const SizedBox(height: 16),
      T('Hesabu ya hisa', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      T('Linganisha kilichopo rafuni na kilichopo kwenye mfumo. Inaonyesha kilichopotea, kilichoibiwa au kilichoandikwa vibaya. Wengi hufanya mara moja kwa mwezi.',
          textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
      const SizedBox(height: 24),
      if (_can(Perm.countStock))
        FilledButton.icon(
          onPressed: _start,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const T('Anza hesabu ya hisa'),
        )
      else
        T('Huna ruhusa ya kuhesabu hisa.', textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
    ]);
  }

  Widget _waiting() {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 24), children: [
      const Icon(Icons.hourglass_top_rounded, size: 56, color: warnAmber),
      const SizedBox(height: 16),
      Text(tr('Hesabu #:n inasubiri idhini', {'n': _count!['id']}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      T('Hisa haijabadilishwa bado. Mwenye ruhusa ya kurekebisha hisa ataikagua.', textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockCountReviewScreen(session: widget.session, countId: asInt(_count!['id']))));
          if (mounted) _load();
        },
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: Text(_can(Perm.adjustStock) ? tr('Kagua na idhinisha') : tr('Fungua')),
      ),
    ]);
  }
}

class _SheetResult {
  const _SheetResult({this.difference, this.next = false});
  final int? difference;
  final bool next;
}

/// Count one product: packs + loose units, or batch by batch.
class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.api, required this.countId, required this.product});

  final ApiClient api;
  final int countId;
  final Map<String, dynamic> product;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  Map<String, dynamic>? _sheet;
  String? _error;
  bool _byBatch = false;
  bool _saving = false;
  Map<String, dynamic>? _line; // the saved result
  Timer? _auto;
  // key ('total' or 'b<batch id>') → one controller per unit
  final Map<String, List<TextEditingController>> _inputs = {};

  List<Map<String, dynamic>> get _units => ((_sheet?['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _batches => ((_sheet?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _auto?.cancel();
    for (final list in _inputs.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.get('stock-counts/${widget.countId}/products/${widget.product['id']}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _sheet = s;
        _byBatch = (s['line'] as Map?)?['by_batch'] == true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<TextEditingController> _ctrl(String key) =>
      _inputs.putIfAbsent(key, () => List.generate(_units.length, (_) => TextEditingController()));

  int _sum(String key) {
    final cs = _ctrl(key);
    var n = 0;
    for (var i = 0; i < cs.length; i++) {
      n += (int.tryParse(cs[i].text) ?? 0) * asInt(_units[i]['base_quantity']);
    }
    return n;
  }

  bool _touched(String key) => _ctrl(key).any((c) => c.text.isNotEmpty);
  List<String> get _keys => _byBatch ? [for (final b in _batches) 'b${b['id']}'] : ['total'];

  /// "3 boksi + 40 vidonge", biggest unit first.
  String _describe(int n) {
    if (_units.isEmpty) return '$n';
    var left = n;
    final parts = <String>[];
    for (var i = 0; i < _units.length; i++) {
      final q = asInt(_units[i]['base_quantity']);
      final k = q == 0 ? 0 : left ~/ q;
      if (k > 0 || (i == _units.length - 1 && parts.isEmpty)) {
        parts.add('$k ${_units[i]['name']}');
        left -= k * q;
      }
    }
    return parts.join(' + ');
  }

  Future<void> _save() async {
    if (!_keys.any(_touched)) {
      setState(() => _error = tr('Andika ulichohesabu (0 kama hakuna kabisa).'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = _byBatch
          ? {'batches': {for (final b in _batches) '${b['id']}': _sum('b${b['id']}')}}
          : {'counted': _sum('total')};
      final r = await widget.api.put('stock-counts/${widget.countId}/products/${widget.product['id']}', body) as Map<String, dynamic>;
      if (!mounted) return;
      final line = r['line'] as Map<String, dynamic>;
      HapticFeedback.mediumImpact();
      setState(() => _line = line);
      if (asInt(line['difference']) == 0) {
        // Exactly right: move on by itself.
        _auto = Timer(const Duration(milliseconds: 900), () {
          if (mounted) Navigator.of(context).pop(_SheetResult(difference: 0, next: true));
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _again() {
    _auto?.cancel();
    for (final list in _inputs.values) {
      for (final c in list) {
        c.clear();
      }
    }
    setState(() => _line = null);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _PackIcon(form: '${widget.product['form'] ?? ''}', size: 1.3),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.product['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  T('Hesabu kilichopo rafuni na stoo, kisha andika hapa.', style: const TextStyle(color: mutedText, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            if (_sheet == null && _error == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: AfyaLoader())),
            if (_sheet != null) ..._form(),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: dangerRed))),
            if (_line != null) _result(),
            const SizedBox(height: 14),
            if (_sheet != null) _actions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _form() {
    final locked = _line != null;
    Widget inputs(String key) => Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < _units.length; i++)
            SizedBox(
              width: 104,
              child: TextField(
                controller: _ctrl(key)[i],
                enabled: !locked,
                autofocus: key == _keys.first && i == 0,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: '${_units[i]['name']}',
                  helperText: asInt(_units[i]['base_quantity']) > 1 ? '×${asInt(_units[i]['base_quantity'])}' : null,
                  hintText: '0',
                ),
              ),
            ),
        ]);
    final total = _keys.fold<int>(0, (s, k) => s + _sum(k));
    return [
      if (_byBatch)
        for (final b in _batches) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text('${b['batch_number'] ?? tr('Bila namba ya batch')} · ${tr('inaisha')} ${b['expiry_date']}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          inputs('b${b['id']}'),
          const Divider(height: 22),
        ]
      else
        inputs('total'),
      if (_keys.any(_touched))
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Jumla: :x', {'x': _describe(total)}), style: const TextStyle(color: mutedText))),
      if (_batches.length > 1 && !locked)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _byBatch = !_byBatch),
            child: Text(_byBatch ? tr('Hesabu jumla tu') : tr('Hesabu kila batch (:n)', {'n': _batches.length})),
          ),
        ),
    ];
  }

  Widget _result() {
    final l = _line!;
    final d = asInt(l['difference']);
    final (bg, fg) = d == 0 ? (primarySoft, primaryStrong) : (d < 0 ? (dangerSoft, dangerRed) : (infoSoft, infoBlue));
    final value = l['value'];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .85, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            d == 0
                ? '✓ ${tr('Sawa kabisa')}'
                : (d < 0 ? tr('Pungufu :x', {'x': _describe(-d)}) : tr('Ziada :x', {'x': _describe(d)})) +
                    (value != null && d != 0 ? ' · ${formatTsh(asInt(value).abs())}' : ''),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg),
          ),
          const SizedBox(height: 4),
          Text(
            d == 0
                ? tr('Rafu na mfumo vinakubaliana: :x.', {'x': _describe(asInt(l['counted']))})
                : tr('Mfumo: :e · Umehesabu: :c.', {'e': _describe(asInt(l['expected'])), 'c': _describe(asInt(l['counted']))}),
          ),
          if (d != 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: T('Hesabu tena kuhakikisha, au endelea: tofauti itasubiri idhini.', style: const TextStyle(color: mutedText, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _actions() {
    if (_line == null) {
      return Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(const _SheetResult(next: true)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const T('Ruka'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const T('Hifadhi'),
          ),
        ),
      ]);
    }
    final d = asInt(_line!['difference']);
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: _again,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: const T('Hesabu tena'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: FilledButton(
          onPressed: () {
            _auto?.cancel();
            Navigator.of(context).pop(_SheetResult(difference: d, next: true));
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: const T('Inayofuata →'),
        ),
      ),
    ]);
  }
}

/// The product's pack, drawn small: box, bottle, tube, vial, jar or carton.
class _PackIcon extends StatelessWidget {
  const _PackIcon({required this.form, this.faded = false, this.size = 1});

  final String form;
  final bool faded;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (w, h, cap) = switch (form) {
      'syrup' => (14.0, 24.0, true),
      'injection' => (11.0, 18.0, true),
      'cream' => (11.0, 26.0, false),
      'capsule' => (16.0, 19.0, true),
      'tablet' => (17.0, 26.0, false),
      _ => (24.0, 18.0, false),
    };
    final colour = faded ? brandGreen.withValues(alpha: .4) : brandGreen;
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Transform.scale(
          scale: size,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (cap) Container(width: w * .55, height: 5, decoration: BoxDecoration(color: form == 'syrup' ? const Color(0xFF3B3B3B) : const Color(0xFFB9C3CA), borderRadius: BorderRadius.circular(1))),
            Container(
              width: w,
              height: h,
              decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(form == 'syrup' ? 4 : 2)),
              alignment: Alignment.center,
              child: Container(width: w - 5, height: h * .24, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(1))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ✓ / −9 / +2, or a dashed circle when not counted yet.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.difference});

  final int? difference;

  @override
  Widget build(BuildContext context) {
    final d = difference;
    if (d == null) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9FB3C8), width: 2)),
      );
    }
    final (bg, text) = d == 0 ? (brandGreen, '✓') : (d < 0 ? (dangerRed, '−${d.abs()}') : (infoBlue, '+$d'));
    return TweenAnimationBuilder<double>(
      key: ValueKey(d),
      tween: Tween(begin: 1.8, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 26),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}

/// Past stock-takes.
class StockCountHistoryScreen extends StatefulWidget {
  const StockCountHistoryScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockCountHistoryScreen> createState() => _StockCountHistoryScreenState();
}

class _StockCountHistoryScreenState extends State<StockCountHistoryScreen> {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.session.api.get('stock-counts') as Map<String, dynamic>;
      if (mounted) setState(() => _list = ((r['counts'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(title: const T('Historia ya hesabu'), backgroundColor: pageBackground),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: dangerRed)))
          : _list == null
              ? const Center(child: AfyaLoader())
              : _list!.isEmpty
                  ? Center(child: T('Bado hakuna hesabu', style: const TextStyle(color: mutedText)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _list!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = _list![i];
                        final at = DateTime.tryParse('${c['started_at']}')?.toLocal();
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text('#${c['id']} · ${at == null ? '' : swahiliDate(at)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(tr(':d zimehesabiwa · tofauti :x', {'d': c['counted'], 'x': asInt(c['short']) + asInt(c['extra'])})),
                            trailing: StatusPill(status: '${c['status']}'),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockCountReviewScreen(session: widget.session, countId: asInt(c['id']))));
                              if (mounted) _load();
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

/// The status of a count, as a small coloured pill.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'counting' => (tr('Inaendelea'), infoSoft, infoBlue),
      'submitted' => (tr('Inasubiri idhini'), warnSoft, warnAmber),
      'approved' => (tr('Imeidhinishwa'), primarySoft, primaryStrong),
      'rejected' => (tr('Imekataliwa'), dangerSoft, dangerRed),
      _ => (tr('Imesitishwa'), cardColor, mutedText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// One count: the differences, and (for whoever may adjust stock) approve or reject.
class StockCountReviewScreen extends StatefulWidget {
  const StockCountReviewScreen({super.key, required this.session, required this.countId});

  final Session session;
  final int countId;

  @override
  State<StockCountReviewScreen> createState() => _StockCountReviewScreenState();
}

class _StockCountReviewScreenState extends State<StockCountReviewScreen> {
  Map<String, dynamic>? _c;
  String? _error;
  final Set<int> _skip = {};
  bool _busy = false;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('stock-counts/${widget.countId}') as Map<String, dynamic>;
      if (mounted) setState(() => _c = r['count'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool get _deciding => _c?['status'] == 'submitted' && widget.session.user!.can(Perm.adjustStock);

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await _api.post('stock-counts/${widget.countId}/approve', {'skip': _skip.toList()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: T('Marekebisho yameingia kwenye hisa.')));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final note = await askText(context, title: tr('Kataa hesabu hii'), label: tr('Sababu'), required: true, danger: true, confirm: tr('Kataa'));
    if (note == null || note.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post('stock-counts/${widget.countId}/reject', {'note': note});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: T('Hesabu imekataliwa; hisa haijabadilishwa.')));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(title: Text(tr('Hesabu #:n', {'n': widget.countId})), backgroundColor: pageBackground),
      bottomNavigationBar: _deciding
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reject,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: dangerRed),
                      child: const T('Kataa'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : _approve,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: const T('Idhinisha marekebisho'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: dangerRed)))
          : c == null
              ? const Center(child: AfyaLoader())
              : RefreshIndicator(onRefresh: _load, child: _body(c)),
    );
  }

  Widget _body(Map<String, dynamic> c) {
    final lines = ((c['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final diffs = lines.where((l) => asInt(l['difference']) != 0).toList();
    final hasValue = c['net_value'] != null;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
      Row(children: [StatusPill(status: '${c['status']}'), const Spacer(), Text(tr('imeanzishwa na :who', {'who': c['started_by'] ?? '—'}), style: const TextStyle(color: mutedText, fontSize: 12))]),
      const SizedBox(height: 14),
      Row(children: [
        _stat('${c['counted']}', tr('zimehesabiwa'), inkColor),
        _stat('${c['matched']}', tr('sawa kabisa'), brandGreen),
        _stat('${c['short']}', tr('pungufu'), dangerRed),
        _stat('${c['extra']}', tr('ziada'), infoBlue),
      ]),
      if (hasValue) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: T('jumla ya tofauti (kwa gharama)', style: const TextStyle(color: mutedText))),
            Text(formatTsh(asInt(c['short_value']) + asInt(c['extra_value'])),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: asInt(c['short_value']) + asInt(c['extra_value']) < 0 ? dangerRed : infoBlue)),
          ]),
        ),
      ],
      if (c['decision_note'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${tr('Maelezo ya uamuzi:')} ${c['decision_note']}')),
      const SizedBox(height: 18),
      T('Tofauti', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      if (_deciding)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: T('Ondoa tiki kwa bidhaa unayotaka ihesabiwe tena: haitabadilishwa. Pungufu inatoka kwenye batch inayoisha mapema kwanza; ziada inaingia kwenye batch ya karibuni.',
              style: const TextStyle(color: mutedText, fontSize: 12)),
        ),
      const SizedBox(height: 8),
      if (diffs.isEmpty) T('Hakuna tofauti: kila kilichohesabiwa kinakubaliana na mfumo.', style: const TextStyle(color: mutedText)),
      for (final l in diffs)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: _lineTile(l),
        ),
    ]);
  }

  Widget _stat(String n, String label, Color colour) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colour)),
            Text(label, style: const TextStyle(fontSize: 11, color: mutedText), textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _lineTile(Map<String, dynamic> l) {
    final id = asInt(l['id']);
    final d = asInt(l['difference']);
    final skipped = l['skipped'] == true || _skip.contains(id);
    final sub = '${tr('Mfumo')}: ${l['expected_text']} · ${tr('Rafuni')}: ${l['counted_text']}';
    final trailing = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('${l['difference_text']}', style: TextStyle(fontWeight: FontWeight.w800, color: d < 0 ? dangerRed : infoBlue)),
      if (l['value'] != null) Text(formatTsh(asInt(l['value'])), style: const TextStyle(fontSize: 12, color: mutedText)),
    ]);
    final title = Text('${l['product']}',
        style: TextStyle(fontWeight: FontWeight.w600, decoration: skipped ? TextDecoration.lineThrough : null, color: skipped ? mutedText : inkColor));
    if (_deciding) {
      return CheckboxListTile(
        value: !_skip.contains(id),
        onChanged: (v) => setState(() => v == true ? _skip.remove(id) : _skip.add(id)),
        controlAffinity: ListTileControlAffinity.leading,
        title: title,
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        secondary: trailing,
      );
    }
    return ListTile(title: title, subtitle: Text(sub, style: const TextStyle(fontSize: 12)), trailing: trailing);
  }
}
