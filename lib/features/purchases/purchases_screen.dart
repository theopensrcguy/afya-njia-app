import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/share_export.dart';
import '../../core/units.dart';
import '../../core/i18n.dart';
import '../../core/range_picker.dart';
import '../../core/smooth.dart';

const _statusLabels = {
  'pending': ('Inasubiri', warnAmber, Color(0xFFFBEFD6)),
  'received': ('Imepokelewa', brandGreen, Color(0xFFDDF3EA)),
  'rejected': ('Imekataliwa', dangerRed, Color(0xFFFDE7E4)),
};

/// Mizigo (v0.44): deliveries waiting for a decision on top, then the
/// history with filters (period, supplier, status, invoice or product), a
/// total for what is shown, and more as you scroll.
///
/// Smooth on purpose: it opens on the last answer (ApiCache) and refreshes;
/// changing a filter keeps the old list on screen, dimmed, until the new one
/// arrives (no blank flash), and a slow old answer can never overwrite a newer
/// one (each request has a number; only the latest is used).
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.session});

  final Session session;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  static const _bg = Color(0xFFF2F6F4);
  static const _ink = Color(0xFF14211D);
  static const _muted = Color(0xFF5B6F69);
  static const _primary = Color(0xFF12644E);

  List<Map<String, dynamic>> _waiting = [];
  bool _waitingLoaded = false;

  // History
  String _period = UiMemory.get('mizigo.period', 'mwezi');
  DateTimeRange? _custom;
  String _supplier = ''; // '' all, 'none', or an id
  String _status = ''; // '' all, received, rejected
  final _q = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _totals;
  List<Map<String, dynamic>> _suppliers = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false; // a filter change or first load in flight
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;
  int _req = 0;
  final _scroll = ScrollController();

  bool get _canConfirm => widget.session.user!.can(Perm.confirmDeliveries);
  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    final w = ApiCache.peek(_api, 'purchases', query: const {'status': 'pending'});
    if (w is List) {
      _waiting = w.cast<Map<String, dynamic>>();
      _waitingLoaded = true;
    }
    final h = ApiCache.peek(_api, 'purchases/history', query: _query(1));
    if (h is Map<String, dynamic>) _take(h, 1);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) _more();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWaiting();
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- data

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'leo' => (today, today),
      'wiki' => (today.subtract(Duration(days: today.weekday - 1)), today),
      'mwezi' => (DateTime(now.year, now.month, 1), today),
      'jana' => (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
      'miezi3' => (DateTime(now.year, now.month - 3, now.day), today),
      'tarehe' => (_custom?.start, _custom?.end),
      _ => (null, null),
    };
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> _query(int page) {
    final (from, to) = _range;
    return {
      if (from != null) 'from': _ymd(from),
      if (to != null) 'to': _ymd(to),
      if (_supplier.isNotEmpty) 'supplier': _supplier,
      if (_status.isNotEmpty) 'status': _status,
      if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      'page': '$page',
    };
  }

  void _take(Map<String, dynamic> h, int page) {
    final items = ((h['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    _items = page == 1 ? items : [..._items, ...items];
    _page = page;
    _hasMore = h['has_more'] == true;
    _totals = (h['totals'] as Map?)?.cast<String, dynamic>();
    _suppliers = ((h['suppliers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    _loadedOnce = true;
  }

  Future<void> _loadWaiting() async {
    try {
      final data = await ApiCache.fetch(_api, 'purchases', query: const {'status': 'pending'}) as List;
      if (mounted) setState(() => (_waiting = data.cast<Map<String, dynamic>>(), _waitingLoaded = true));
    } on ApiException catch (_) {
      if (mounted) setState(() => _waitingLoaded = true);
    }
  }

  Future<void> _loadHistory() async {
    final my = ++_req;
    setState(() => (_loading = true, _error = null));
    try {
      final h = await ApiCache.fetch(_api, 'purchases/history', query: _query(1)) as Map<String, dynamic>;
      if (!mounted || my != _req) return; // a newer filter was chosen meanwhile
      setState(() => _take(h, 1));
    } on ApiException catch (e) {
      if (mounted && my == _req) setState(() => _error = e.message);
    } finally {
      if (mounted && my == _req) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (!_hasMore || _loading || _loadingMore) return;
    final my = _req;
    setState(() => _loadingMore = true);
    try {
      final h = await _api.get('purchases/history', query: _query(_page + 1)) as Map<String, dynamic>;
      if (mounted && my == _req) setState(() => _take(h, _page + 1));
    } on ApiException catch (_) {
      // The list stays; scrolling again tries again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadWaiting(), _loadHistory()]);
  }

  void _filterChanged() {
    tick();
    _loadHistory();
  }

  Future<void> _open(Map<String, dynamic> p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseReviewScreen(session: widget.session, purchase: p)),
    );
    if (changed == true && mounted) _refresh();
  }

  // ----------------------------------------------------------- filters

  Future<void> _pickPeriod(String k) async {
    if (k == 'tarehe') {
      final now = DateTime.now();
      final r = await pickDayOrRange(context, first: DateTime(now.year - 3), last: now, initial: _custom, maxDays: 3 * 366);
      if (r == null) return;
      _custom = r;
    }
    setState(() => _period = k);
    if (k != 'tarehe') UiMemory.set('mizigo.period', k);
    _filterChanged();
  }

  Future<void> _pickSupplier() async {
    final picked = await pickOne<String>(
      context,
      title: tr('Chagua msambazaji'),
      selected: _supplier,
      options: [
        PickOption('', tr('Wasambazaji wote')),
        PickOption('none', tr('Bila msambazaji')),
        for (final sp in _suppliers) PickOption('${sp['id']}', '${sp['name']}'),
      ],
    );
    if (picked == null || picked == _supplier || !mounted) return;
    setState(() => _supplier = picked);
    _filterChanged();
  }

  String get _supplierLabel => switch (_supplier) {
        '' => tr('Wasambazaji wote'),
        'none' => tr('Bila msambazaji'),
        _ => '${_suppliers.firstWhere((s) => '${s['id']}' == _supplier, orElse: () => {'name': '…'})['name']}',
      };

  // ----------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_canConfirm ? tr('Mizigo') : tr('Mizigo yangu'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // Share the deliveries as the list stands (v0.48.2): PDF or Excel, WhatsApp or a link.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: tr('Shiriki mizigo'),
                icon: const Icon(Icons.ios_share_rounded, color: brandGreen, size: 20),
                onPressed: () {
                  final q = _query(1)..remove('page');
                  shareDeliveries(context,
                      api: _api,
                      from: q['from'],
                      to: q['to'],
                      supplier: q['supplier'],
                      status: q['status'],
                      q: q['q'] ?? '',
                      describe: [
                        _periodLabel,
                        if (_supplier.isNotEmpty) _supplierLabel,
                        if (_status == 'received') tr('Zilizopokelewa') else if (_status == 'rejected') tr('Zilizokataliwa'),
                        if (_q.text.trim().isNotEmpty) '“${_q.text.trim()}”',
                      ]);
                },
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverList.list(children: [
                ..._waitingSection(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 10, 4, 10),
                  child: T('Historia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
                ),
                // Two half-width filters that always fit, then the status switch.
                Row(children: [
                  Expanded(
                    child: DropPill(
                      label: tr('Kipindi'),
                      value: _periodLabel,
                      active: _period != 'zote',
                      onTap: _choosePeriod,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropPill(label: tr('Msambazaji'), value: _supplierLabel, active: _supplier.isNotEmpty, onTap: _pickSupplier),
                  ),
                ]),
                const SizedBox(height: 10),
                SlidingSegments<String>(
                  values: const ['', 'received', 'rejected'],
                  labels: [tr('Zote'), tr('Zimepokelewa'), tr('Zimekataliwa')],
                  selected: _status,
                  height: 42,
                  fontSize: 13,
                  onChanged: (v) {
                    setState(() => _status = v);
                    _filterChanged();
                  },
                ),
                const SizedBox(height: 10),
                _searchBox(),
                const SizedBox(height: 12),
                _totalsCard(),
                const SizedBox(height: 4),
              ]),
            ),
            // The list: dimmed while a new filter loads, never blank.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverAnimatedOpacity(
                opacity: _loading && _loadedOnce ? .45 : 1,
                duration: Motion.of(context, Motion.fast),
                sliver: _historyList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _waitingSection() {
    if (!_waitingLoaded) return [const Skeleton(height: 120, radius: 20)];
    if (_waiting.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, color: _primary),
            const SizedBox(width: 10),
            Expanded(child: T(_canConfirm ? 'Hakuna mzigo unaosubiri uthibitisho.' : 'Hakuna mzigo wako unaosubiri.', style: const TextStyle(color: _ink))),
          ]),
        ),
      ];
    }
    return [for (final p in _waiting) Padding(padding: const EdgeInsets.only(bottom: 10), child: _waitingCard(p))];
  }

  Widget _waitingCard(Map<String, dynamic> p) {
    final lines = (p['lines'] as List?) ?? const [];
    final at = parseDate(p['received_at']);
    final inv = p['invoice_total'];
    final diff = inv == null ? 0 : asInt(p['total_cost']) - asInt(inv);
    return Pressable(
      onTap: () => _open(p),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF2F5FC4), width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFEAF0FD), borderRadius: BorderRadius.circular(99)),
              child: T(_canConfirm ? 'Inasubiri uthibitisho' : 'Inasubiri', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2F5FC4))),
            ),
            const SizedBox(width: 8),
            if (at != null) Text(timeAgo(at.toLocal()), style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(p['supplier'] as Map?)?['name'] ?? tr('Bila msambazaji')}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 3),
                Text(
                  [if (p['invoice_number'] != null) tr('Ankara :a', {'a': p['invoice_number']}), tr('bidhaa :n', {'n': lines.length}), '${p['received_by'] ?? ''}']
                      .where((x) => x.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatTsh(asInt(p['total_cost'])), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
              if (inv != null && diff != 0)
                Text(tr('ankara: :a (:b)', {'a': formatTsh(asInt(inv)), 'b': '${diff > 0 ? '+' : '−'}${formatTsh(diff.abs()).replaceFirst('TSh ', '')}'}),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7A4A12))),
            ]),
          ]),
          const SizedBox(height: 12),
          Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(13)),
            child: T(_canConfirm ? 'Angalia na thibitisha' : 'Angalia', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ]),
      ),
    );
  }

  static const _periods = [('leo', 'Leo'), ('wiki', 'Wiki hii'), ('mwezi', 'Mwezi huu'), ('jana', 'Mwezi uliopita'), ('miezi3', 'Miezi 3'), ('zote', 'Zote'), ('tarehe', 'Tarehe…')];

  String get _periodLabel {
    if (_period == 'tarehe' && _custom != null) {
      return '${_custom!.start.day}/${_custom!.start.month} – ${_custom!.end.day}/${_custom!.end.month}';
    }
    return tr(_periods.firstWhere((p) => p.$1 == _period, orElse: () => _periods[2]).$2);
  }

  Future<void> _choosePeriod() async {
    final picked = await pickOne<String>(
      context,
      title: tr('Chagua kipindi'),
      selected: _period,
      options: [for (final (k, l) in _periods) PickOption(k, tr(l), sub: k == 'tarehe' ? tr('Chagua siku ya kuanzia na ya mwisho') : null)],
    );
    if (picked != null && mounted) _pickPeriod(picked);
  }

  Widget _searchBox() => Container(
        height: 44,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFDCE5E1), width: 1.5)),
        child: Row(children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, size: 19, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: (_) {
                setState(() {});
                // Wait for a pause in typing: one request, not one per letter.
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _loadHistory);
              },
              decoration: InputDecoration(
                hintText: tr('Namba ya ankara au bidhaa'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14, color: _ink),
            ),
          ),
          if (_q.text.isNotEmpty)
            IconButton(
              tooltip: tr('Futa'),
              icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
              onPressed: () {
                _q.clear();
                setState(() {});
                _loadHistory();
              },
            ),
        ]),
      );

  Widget _totalsCard() {
    final (from, to) = _range;
    String d(DateTime x) => '${x.day} ${tr(const ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'][x.month - 1])}';
    final range = from == null ? tr('Zote') : (from == to ? d(from) : '${d(from)} – ${d(to!)}');
    final cost = _totals?['cost'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(range, style: const TextStyle(fontSize: 12, color: Color(0xFFB7D3C9))),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              child: Text(_totals == null ? '…' : tr('Mizigo :n', {'n': _totals!['count']}),
                  key: ValueKey('${_totals?['count']}'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),
        if (cost != null)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const T('kwa bei ya kununua', style: TextStyle(fontSize: 12, color: Color(0xFFB7D3C9))),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              child: Text(formatTsh(asInt(cost)), key: ValueKey('$cost'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
      ]),
    );
  }

  Widget _historyList() {
    if (!_loadedOnce) {
      if (_error != null) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _ink)),
              TextButton(onPressed: _loadHistory, child: const T('Jaribu tena')),
            ]),
          ),
        );
      }
      return SliverList.list(children: [
        for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(top: 10), child: Skeleton(height: 68, radius: 16)),
      ]);
    }
    if (_items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(children: [
            const Icon(Icons.local_shipping_outlined, size: 36, color: Color(0xFFB8C4C0)),
            const SizedBox(height: 8),
            const T('Hakuna mzigo kwenye kichujio hiki.', style: TextStyle(color: _muted)),
            if (_period != 'zote' || _supplier.isNotEmpty || _status.isNotEmpty || _q.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  _q.clear();
                  setState(() => (_period = 'zote', _supplier = '', _status = ''));
                  _filterChanged();
                },
                child: const T('Onyesha mizigo yote'),
              ),
          ]),
        ),
      );
    }
    // Grouped by day, newest first.
    final rows = <Widget>[];
    String? day;
    for (final p in _items) {
      final at = parseDate(p['received_at'])?.toLocal();
      final label = at == null ? '' : swahiliDate(at).toUpperCase();
      if (label != day) {
        day = label;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4, color: _muted)),
        ));
      }
      rows.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _historyRow(p)));
    }
    if (_loadingMore) rows.add(const Padding(padding: EdgeInsets.only(top: 4), child: Skeleton(height: 68, radius: 16)));
    if (!_hasMore && _items.length > 8) {
      rows.add(const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: T('Hiyo ndiyo yote.', style: TextStyle(fontSize: 12, color: _muted)))));
    }
    return SliverList.list(children: rows);
  }

  Widget _historyRow(Map<String, dynamic> p) {
    final no = p['status'] == 'rejected';
    final lines = (p['lines'] as List?) ?? const [];
    return Pressable(
      onTap: () => _open(p),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: no ? const Color(0xFFFBE9E5) : const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.local_shipping_outlined, size: 19, color: no ? const Color(0xFFA8321F) : _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${(p['supplier'] as Map?)?['name'] ?? (p['invoice_number'] == null ? tr('Bila msambazaji') : '${p['invoice_number']}')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
              const SizedBox(height: 2),
              Text(
                [if (p['invoice_number'] != null) '${p['invoice_number']}', tr('bidhaa :n', {'n': lines.length}), '${p['received_by'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              if (no && p['rejected_reason'] != null)
                Text(tr('Imekataliwa: :a', {'a': p['rejected_reason']}),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA8321F))),
            ]),
          ),
          const SizedBox(width: 8),
          Text(
            formatTsh(asInt(p['total_cost'])),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: no ? const Color(0xFF8A9B95) : _ink,
              decoration: no ? TextDecoration.lineThrough : null,
            ),
          ),
        ]),
      ),
    );
  }
}

/// One delivery in full. For the owner, a pending one ends with
/// Kataa (reason required) / Thibitisha (stock goes up now).
class PurchaseReviewScreen extends StatefulWidget {
  const PurchaseReviewScreen({super.key, required this.session, required this.purchase});

  final Session session;
  final Map<String, dynamic> purchase;

  @override
  State<PurchaseReviewScreen> createState() => _PurchaseReviewScreenState();
}

class _PurchaseReviewScreenState extends State<PurchaseReviewScreen> {
  late Map<String, dynamic> _p = widget.purchase;
  Future<dynamic>? _photo;
  bool _busy = false;

  ApiClient get _api => widget.session.api;
  bool get _canConfirm => widget.session.user!.can(Perm.confirmDeliveries);

  /// Four eyes: nobody confirms a delivery they recorded (the server refuses too).
  bool get _mine => asInt(_p['received_by_id']) == widget.session.user!.id;

  bool get _canPrice => widget.session.user!.can(Perm.editPrices);

  // ---- products this delivery brings for the first time
  final Map<String, TextEditingController> _priceFields = {}; // "productId:unit"
  final Map<int, TextEditingController> _nameFields = {}; // off-catalogue names, editable

  List<Map<String, dynamic>> get _newProducts =>
      ((_p['new_products'] as List?) ?? const []).cast<Map<String, dynamic>>().where((n) => n['is_active'] != true).toList();

  TextEditingController _price(int id, String unit) => _priceFields.putIfAbsent('$id:$unit', TextEditingController.new);

  /// New products still without a price for every unit: Thibitisha waits for them.
  int get _unpriced => _newProducts.where((n) {
        if (n['needs_price'] != true) return false;
        final units = ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
        return units.any((u) => (moneyValue(_price(asInt(n['id']), '${u['name']}').text) ?? 0) < 1);
      }).length;

  /// What this delivery paid per base unit for a product (for the profit hint).
  int? _unitCost(int productId) {
    for (final l in ((_p['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      if (asInt(l['product_id']) == productId && l['unit_cost'] != null) return asInt(l['unit_cost']);
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in [..._priceFields.values, ..._nameFields.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The photo is private on the server: fetched with the token, owner only.
    if (_canConfirm && _p['has_photo'] == true) _photo = _api.getBytes('purchases/${_p['id']}/photo');
  }

  Future<void> _decide(bool accept) async {
    String? reason;
    if (!accept) {
      reason = await askText(context,
          title: tr('Kataa mzigo'), label: tr('Sababu'), hint: tr('mfano: bei hailingani na ankara'), required: true, danger: true, confirm: tr('Kataa'));
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> body = accept
          ? {
              if (_newProducts.isNotEmpty)
                'products': [
                  for (final n in _newProducts)
                    {
                      'id': asInt(n['id']),
                      if (_nameFields[asInt(n['id'])] != null) 'name': _nameFields[asInt(n['id'])]!.text.trim(),
                      'prices': {
                        for (final u in ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>())
                          if ((moneyValue(_price(asInt(n['id']), '${u['name']}').text) ?? 0) >= 1)
                            '${u['name']}': moneyValue(_price(asInt(n['id']), '${u['name']}').text)!,
                      },
                    },
                ],
            }
          : {'reason': ?reason};
      final res = await _api.post('purchases/${_p['id']}/${accept ? 'confirm' : 'reject'}', body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _p = res);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? tr('Imethibitishwa. Hisa imeongezeka.') : tr('Mzigo umekataliwa.')),
      ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerRed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _p['status'] == 'pending';
    final (label, fg, bg) = _statusLabels[_p['status']] ?? ('${_p['status']}', mutedText, mintSoft);
    final at = parseDate(_p['received_at']);
    final lines = ((_p['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final invoiceTotal = _p['invoice_total'] == null ? null : asInt(_p['invoice_total']);
    final total = asInt(_p['total_cost']);

    return Scaffold(
      appBar: AppBar(
        title: const T('Mzigo'),
        backgroundColor: pageBackground,
        actions: [
          // The receiving note on A4: print / PDF, WhatsApp, or a link (v0.48.2).
          PopupMenuButton<String>(
            tooltip: tr('Chapisha au shiriki'),
            icon: const Icon(Icons.ios_share_rounded),
            onSelected: (how) => shareDelivery(context, api: widget.session.api, purchaseId: asInt(_p['id']), how: how),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: ListTile(dense: true, leading: const Icon(Icons.print_outlined), title: T('Chapisha / PDF'))),
              PopupMenuItem(value: 'wa', child: ListTile(dense: true, leading: const Icon(Icons.chat_outlined), title: T('Tuma kwa WhatsApp'))),
              PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: const Icon(Icons.link_rounded), title: T('Nakili kiungo'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 22),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(tr(label), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  _kv(tr('Imerekodiwa na'), '${_p['received_by'] ?? ''} · ${at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}'}'),
                  _kv(tr('Msambazaji'), '${(_p['supplier'] as Map?)?['name'] ?? '—'}'),
                  _kv(tr('Ankara'), '${_p['invoice_number'] ?? '—'}'),
                  if (_p['confirmed_by'] != null) _kv(_p['status'] == 'rejected' ? tr('Imekataliwa na') : tr('Imethibitishwa na'), '${_p['confirmed_by']}'),
                  if (_p['rejected_reason'] != null) _kv(tr('Sababu'), '${_p['rejected_reason']}'),
                ]),
              ),
              if (_photo != null) _photoThumb(),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: softCard(radius: 22),
            child: Column(children: [
              for (var i = 0; i < lines.length; i++) _line(lines[i], last: i == lines.length - 1),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: T('Jumla ya mzigo', style: TextStyle(color: mutedText))),
                Text(formatTsh(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              if (invoiceTotal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    invoiceTotal == total
                        ? tr('✓ Inalingana na ankara (:a)', {'a': formatTsh(invoiceTotal)})
                        : tr('Ankara inasema :a: tofauti :b', {'a': formatTsh(invoiceTotal), 'b': formatTsh((invoiceTotal - total).abs())}),
                    style: TextStyle(fontWeight: FontWeight.w800, color: invoiceTotal == total ? brandGreen : dangerRed),
                  ),
                ),
            ]),
          ),
          if (_canConfirm && pending && !_mine)
            for (final n in _newProducts) _newProductCard(n),
          if (_canConfirm && pending && _mine)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: T('Huu ni mzigo uliourekodi mwenyewe: mtu mwingine ndiye athibitishe.',
                  textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
            ),
          if (_canConfirm && pending && !_mine) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: dangerRed,
                    side: const BorderSide(color: dangerRed, width: 2),
                  ),
                  child: const T('Kataa'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  // A product without a price would reach the counter and sell for nothing.
                  onPressed: _busy || _unpriced > 0 ? null : () => _decide(true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_busy ? tr('Inatuma…') : tr('Thibitisha mzigo')),
                ),
              ),
            ]),
            if (_unpriced > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _canPrice ? tr('Weka bei ya bidhaa mpya :unpriced kwanza.', {'unpriced': _unpriced}) : tr('Mzigo huu una bidhaa mpya bila bei: anayeweza kuweka bei athibitishe.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: warnAmber, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// One product arriving for the first time: its name (editable if typed by
  /// hand), and a price per unit when it has none yet, with the profit live.
  Widget _newProductCard(Map<String, dynamic> n) {
    final id = asInt(n['id']);
    final units = ((n['units'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final offCatalogue = n['off_catalogue'] == true;
    final needsPrice = n['needs_price'] == true;
    final cost = _unitCost(id);
    if (offCatalogue) _nameFields.putIfAbsent(id, () => TextEditingController(text: '${n['name']}'));
    Widget badge(String t, Color fg, Color bg) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
        );
    final missing = needsPrice && units.any((u) => (moneyValue(_price(id, '${u['name']}').text) ?? 0) < 1);

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: missing ? const Color(0xFFE0A93B) : Colors.transparent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          badge(tr('BIDHAA MPYA'), brandGreen, const Color(0xFFDDF3EA)),
          if (offCatalogue) badge(tr('nje ya katalogi'), warnAmber, const Color(0xFFFBEFD6)),
        ]),
        const SizedBox(height: 8),
        if (offCatalogue) ...[
          TextField(
            controller: _nameFields[id],
            decoration: InputDecoration(labelText: tr('Jina (limeandikwa na msaidizi: liangalie)')),
          ),
        ] else
          Text('${n['name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        if (needsPrice && !_canPrice)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: T('Haina bei bado. Huna ruhusa ya kuweka bei.', style: TextStyle(color: warnAmber)),
          ),
        if (_canPrice)
          for (final u in units)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _price(id, '${u['name']}'),
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInput()],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '${needsPrice ? tr('Bei ya kuuza') : tr('Bei (si lazima kubadilisha)')}: '
                      '${unitLabel('${u['name']}')}${asInt(u['base_quantity']) > 1 ? ' (${asInt(u['base_quantity'])})' : ''}',
                  hintText: needsPrice ? null : formatTsh(asInt(u['price'])),
                  helperText: _profit(cost, asInt(u['base_quantity']), moneyValue(_price(id, '${u['name']}').text)),
                ),
              ),
            ),
      ]),
    );
  }

  /// "unanunua TSh 35 · faida 50%"
  String? _profit(int? costPerBase, int size, int? price) {
    if (costPerBase == null || !widget.session.user!.can(Perm.viewCosts)) return null;
    final cost = costPerBase * size;
    if (price == null || price < 1) return tr('Unanunua :a', {'a': formatTsh(cost)});
    final pct = ((price - cost) * 100 / price).round();
    return tr('Unanunua :a · :b', {'a': formatTsh(cost), 'b': pct < 0 ? tr('HASARA') : tr('faida :pct%', {'pct': pct})});
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: mutedText)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _photoThumb() {
    return FutureBuilder<dynamic>(
      future: _photo,
      builder: (context, snap) {
        final bytes = snap.data;
        return GestureDetector(
          onTap: bytes == null
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (d) => Dialog(
                      insetPadding: const EdgeInsets.all(8),
                      child: InteractiveViewer(child: Image.memory(bytes)), // pinch to zoom the invoice
                    ),
                  ),
          child: Container(
            width: 96,
            height: 124,
            decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover)
                : Center(
                    child: snap.hasError
                        ? const Icon(Icons.broken_image_outlined, color: mutedText)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
      },
    );
  }

  Widget _line(Map<String, dynamic> l, {required bool last}) {
    final packName = l['pack_name'] as String?;
    final size = asInt(l['pack_size']);
    final packs = asInt(l['packs']);
    final expiry = parseDate(l['expiry_date']);
    final pack = size == 1 || packName == null ? '$packs' : '$packs ${unitLabel(packName, packs)} × $size = ${asInt(l['quantity'])}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${l['product']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(formatTsh(asInt(l['line_total'])), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Text(
          tr(':pack · :batch · inaisha :exp · :cost kila moja', {
            'pack': pack,
            'batch': l['batch_number'],
            'exp': expiry == null ? '' : '${expiry.month.toString().padLeft(2, '0')}/${expiry.year}',
            'cost': formatTsh(asInt(l['pack_cost'])),
          }),
          style: const TextStyle(fontSize: 12, color: mutedText),
        ),
      ]),
    );
  }
}
