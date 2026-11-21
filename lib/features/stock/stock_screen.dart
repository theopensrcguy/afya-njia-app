import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/product_photo.dart';
import '../../core/scan_once.dart';
import '../../core/share_export.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/empty_shelves.dart';
import '../../core/order_basket.dart';
import '../bulk/bulk_entry_screen.dart';
import '../orders/reorder_screen.dart';
import '../purchases/receive_screen.dart';
import 'deletions_screen.dart';
import 'product_stock_screen.dart';
import 'rafu_view.dart';
import 'stock_count_screen.dart';
import 'stock_look.dart';

const _bg = Color(0xFFF2F6F4);
const _ink = Color(0xFF14211D);
const _muted = Color(0xFF5B6F69);
const _line = Color(0xFFDCE5E1);
const _primary = Color(0xFF12644E);

/// Hisa (v0.44, from the "Afya Njia app stock screens" canvas): one screen,
/// two views of the same answer (GET stock):
///
///  - Orodha: every product as a row (pack in its form, aisle, tags, level,
///    expiry, stock, price), filters with counts, sorting, search or scan.
///  - Rafu:   the shop as aisles of shelves (rafu_view.dart).
///
/// It opens on what it showed last time (ApiCache) and refreshes quietly;
/// the view, filter and sort are remembered (UiMemory); switching views is a
/// slide, not a new page, so nothing reloads.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.session, this.initialFilter, this.startWithScan = false});

  final Session session;

  /// zote | chache | hazipo | muda | zimeisha | haina | mpya. Given by home's
  /// "Fungua orodha: …"; otherwise the last one used.
  final String? initialFilter;

  /// Home's "Skani": open the camera at once and go to the product scanned.
  final bool startWithScan;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  int _deletions = 0;
  bool _fabWide = true;

  late String _filter = widget.initialFilter ?? UiMemory.get('stock.filter', 'zote');
  String _sort = UiMemory.get('stock.sort', 'hali');
  String _view = UiMemory.get('stock.view', 'orodha');
  String _rafuMode = UiMemory.get('stock.rafuMode', 'hisa');
  // Aina, many at once (empty = every aisle; 0 = no aisle). Bei: a range on the row's price (null = any).
  Set<int> _cats = {...UiMemory.get<Set<int>>('stock.cats', const {})};
  RangeValues? _price = UiMemory.get<RangeValues?>('stock.price', null);
  bool _panel = false; // Vichujio unfolded
  // Ordering from Hisa (v0.48.3): what's already in Agiza's basket, and rows held to pick several.
  Set<int> _inBasket = {};
  final Set<int> _picked = {};
  bool get _canOrder => _can(Perm.prepareOrders);
  final _q = TextEditingController();

  ApiClient get _api => widget.session.api;
  bool _can(String p) => widget.session.user!.can(p);
  bool get _costs => _can(Perm.viewCosts);

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _view = 'orodha'; // asked for a filtered list: show the list
    }
    // The last answer at once; the fresh one replaces it when it comes.
    final cached = ApiCache.peek(_api, 'stock');
    if (cached is Map<String, dynamic>) _data = cached;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (widget.startWithScan) _scan();
    });
    _q.addListener(() => setState(() {}));
    if (_canOrder) _readBasket();
  }

  Future<void> _readBasket() async {
    final ids = await OrderBasket.ids(widget.session);
    if (mounted) setState(() => _inBasket = ids);
  }

  /// Into Agiza's basket (1 pack of the biggest unit). Tapping again takes it out.
  Future<void> _toBasket(List<Map<String, dynamic>> products) async {
    if (products.isEmpty) return;
    tick();
    final fresh = [for (final p in products) if (!_inBasket.contains(asInt(p['id']))) p];
    for (final p in fresh) {
      await OrderBasket.addFromStock(widget.session, p);
    }
    setState(() {
      _inBasket.addAll(fresh.map((p) => asInt(p['id'])));
      _picked.clear();
    });
    if (!mounted || fresh.isEmpty) return;
    final m = ScaffoldMessenger.of(context);
    showUndoSnack(
      m,
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(fresh.length == 1 ? tr(':a imewekwa kikapuni', {'a': '${fresh.first['name']}'}) : tr('Bidhaa :n zimewekwa kikapuni', {'n': fresh.length})),
        action: SnackBarAction(
          label: tr('Rudisha'),
          onPressed: () async {
            for (final p in fresh) {
              await OrderBasket.remove(widget.session, p['id']);
            }
            if (mounted) setState(() => _inBasket.removeAll(fresh.map((p) => asInt(p['id']))));
          },
        ),
      ),
    );
  }

  Future<void> _fromBasket(Map<String, dynamic> p) async {
    tick();
    await OrderBasket.remove(widget.session, p['id']);
    if (mounted) setState(() => _inBasket.remove(asInt(p['id'])));
  }

  void _togglePick(Map<String, dynamic> p) {
    tick();
    final id = asInt(p['id']);
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }

  Future<void> _openBasket() async {
    tick();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReorderScreen(session: widget.session)));
    if (mounted) {
      _readBasket();
      _load();
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiCache.fetch(_api, 'stock') as Map<String, dynamic>;
      if (mounted) setState(() => (_data = data, _error = null));
    } on ApiException catch (e) {
      // Keep what is on screen; say what went wrong above it.
      if (mounted) setState(() => _error = e.message);
    }
    _api.get('stock-deletions').then((r) {
      if (mounted) setState(() => _deletions = ((r as Map)['requests'] as List).length);
    }).catchError((_) {});
  }

  void _set(String key, String value, void Function(String) apply) {
    setState(() => apply(value));
    UiMemory.set(key, value);
  }

  List<Map<String, dynamic>> get _all => (((_data ?? const {})['products'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Map<int, String> get _catNames => {
        for (final c in (((_data ?? const {})['categories'] as List?) ?? const []).cast<Map<String, dynamic>>()) asInt(c['id']): '${c['name']}',
      };

  bool _match(Map<String, dynamic> p, String f) => switch (f) {
        'chache' => p['is_out'] == true || p['is_low'] == true,
        'hazipo' => p['is_out'] == true,
        'muda' => p['is_expiring'] == true,
        'zimeisha' => p['is_expired'] == true,
        'haina' => p['needs_price'] == true,
        'mpya' => p['never_stocked'] == true,
        _ => true,
      };

  bool _inCats(Map<String, dynamic> p, Set<int> cats) => cats.isEmpty || cats.contains(asInt(p['category_id']));

  bool _inPrice(Map<String, dynamic> p) {
    final r = _price;
    if (r == null) return true;
    final v = priceOf(p);
    return v >= r.start && v <= r.end;
  }

  /// Highest price on the list, rounded up, for the Bei slider.
  double get _priceMax {
    var m = 0;
    for (final p in _all) {
      final v = priceOf(p);
      if (v > m) m = v;
    }
    if (m <= 0) return 0;
    final step = m > 100000 ? 10000 : (m > 10000 ? 1000 : 100);
    return ((m + step - 1) ~/ step * step).toDouble();
  }

  int get _activeFilters => (_filter != 'zote' ? 1 : 0) + _cats.length + (_price != null ? 1 : 0) + (_sort != 'hali' ? 1 : 0);

  void _saveFilters() {
    UiMemory.set('stock.filter', _filter);
    UiMemory.set('stock.cats', {..._cats});
    UiMemory.set('stock.price', _price);
    UiMemory.set('stock.sort', _sort);
  }

  void _clearAll() {
    tick();
    setState(() => (_filter = 'zote', _cats = {}, _price = null, _sort = 'hali'));
    _saveFilters();
  }

  List<Map<String, dynamic>> get _rows {
    final q = _q.text.trim().toLowerCase();
    final cats = _catNames;
    final rows = _all.where((p) {
      if (!_match(p, _filter) || !_inCats(p, _cats) || !_inPrice(p)) return false;
      if (q.isEmpty) return true;
      return '${p['name']}'.toLowerCase().contains(q) || (cats[asInt(p['category_id'])] ?? '').toLowerCase().contains(q);
    }).toList();
    int byName(Map a, Map b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    switch (_sort) {
      case 'jina':
        rows.sort(byName);
      case 'hisa':
        rows.sort((a, b) => asInt(a['on_hand']).compareTo(asInt(b['on_hand'])));
      case 'muda':
        rows.sort((a, b) => (daysToExpiry(a) ?? 1 << 30).compareTo(daysToExpiry(b) ?? 1 << 30));
      case 'thamani':
        rows.sort((a, b) => asInt(b['value_at_cost']).compareTo(asInt(a['value_at_cost'])));
      case 'bei':
        rows.sort((a, b) => priceOf(a).compareTo(priceOf(b)));
      default: // hali: worst first, then by name
        rows.sort((a, b) {
          final s = stockStates.indexOf(stateOf(a)).compareTo(stockStates.indexOf(stateOf(b)));
          return s != 0 ? s : byName(a, b);
        });
    }
    return rows;
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load(); // stock, prices or units may have changed
  }

  void _openProduct(Map<String, dynamic> p) =>
      _push(ProductStockScreen(session: widget.session, productId: asInt(p['id']), name: '${p['name']}'));

  Future<void> _scan() async {
    final code = await scanOnce(context, title: tr('Skani barcode ya bidhaa'));
    if (code == null || !mounted) return;
    try {
      final r = await _api.get('products/barcode/${Uri.encodeComponent(code)}') as Map<String, dynamic>;
      final p = (r['product'] as Map<String, dynamic>?) ?? r;
      if (mounted) _openProduct(p);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == 404 ? tr('Barcode hii haijulikani bado.') : e.message)));
    }
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: !_can(Perm.receive) || _picked.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _push(ReceiveScreen(session: widget.session)),
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              isExtended: _fabWide,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const T('Pokea mzigo'),
            ),
      bottomNavigationBar: _canOrder ? _basketBar() : null,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _topBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SlidingSegments<String>(
              values: const ['orodha', 'rafu'],
              labels: [tr('Orodha'), tr('Rafu')],
              icons: const [Icons.format_list_bulleted_rounded, Icons.shelves],
              selected: _view,
              onChanged: (v) => _set('stock.view', v, (x) => _view = x),
            ),
          ),
          if (_error != null && _data != null) _errorStrip(),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              // The big "Pokea mzigo" shrinks to its icon while scrolling down, so it never hides a row.
              onNotification: (n) {
                final wide = n.direction != ScrollDirection.reverse;
                if (n.direction != ScrollDirection.idle && wide != _fabWide) setState(() => _fabWide = wide);
                return false;
              },
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                switchInCurve: Motion.curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(a), child: child),
                ),
                child: _data == null
                    ? KeyedSubtree(key: const ValueKey('wait'), child: _error != null ? _errorFull() : const _ListSkeleton())
                    : _view == 'orodha'
                        ? KeyedSubtree(key: const ValueKey('orodha'), child: _orodha())
                        : KeyedSubtree(
                            key: const ValueKey('rafu'),
                            child: _all.isEmpty
                                ? LayoutBuilder(
                                    builder: (context, box) => SingleChildScrollView(
                                      child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: Center(child: _emptyShop())),
                                    ),
                                  )
                                : RafuView(
                              products: _all,
                              categories: _catNames,
                              mode: _rafuMode,
                              onMode: (v) => _set('stock.rafuMode', v, (x) => _rafuMode = x),
                              search: _searchField(),
                              query: _q.text,
                              onRefresh: _load,
                              onOpen: _openProduct,
                              onReceive: _can(Perm.receive) ? () => _push(ReceiveScreen(session: widget.session)) : null,
                              onReorder: _can(Perm.prepareOrders) ? () => _push(ReorderScreen(session: widget.session)) : null,
                            ),
                          ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _square(IconData icon, String label, VoidCallback onTap, {int badge = 0}) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              backgroundColor: const Color(0xFF2F5FC4),
              child: Icon(icon, size: 21, color: _ink),
            ),
          ),
        ),
      );

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        if (Navigator.of(context).canPop()) ...[
          _square(Icons.chevron_left_rounded, tr('Rudi'), () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
        ],
        const Expanded(child: T('Hisa', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -0.4))),
        const SizedBox(width: 8),
        if (_can(Perm.countStock) || _can(Perm.adjustStock)) ...[
          _square(Icons.fact_check_outlined, tr('Hesabu ya hisa'), () => _push(StockCountScreen(session: widget.session))),
          const SizedBox(width: 8),
        ],
        _square(Icons.delete_sweep_outlined, tr('Maombi ya kufuta hisa'), () => _push(DeletionsScreen(session: widget.session)), badge: _deletions),
        const SizedBox(width: 8),
        _square(Icons.ios_share_rounded, tr('Pakua hisa (PDF / Excel)'), _export),
      ]),
    );
  }

  /// The stock as it stands, as PDF or Excel, with the filters on screen (v0.47).
  void _export() {
    final server = const {'chache': 'chache', 'hazipo': 'zimeisha', 'muda': 'muda', 'zimeisha': 'zimeisha_muda'}[_filter] ?? 'zote';
    final status = _statusDefs.firstWhere((d) => d.$1 == _filter, orElse: () => _statusDefs.first);
    final cats = {for (final c in ((_data?['categories'] as List?) ?? const []).cast<Map<String, dynamic>>()) asInt(c['id']): '${c['name']}'};
    shareStock(context,
        api: widget.session.api,
        filter: server,
        cats: _cats,
        q: _q.text,
        describe: [
          if (server != 'zote') tr(status.$2),
          for (final c in _cats) c == 0 ? tr('Bila aina') : (cats[c] ?? '…'),
          if (_q.text.trim().isNotEmpty) '"${_q.text.trim()}"',
        ]);
  }

  Widget _searchField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line, width: 1.5)),
      child: Row(children: [
        const SizedBox(width: 14),
        const Icon(Icons.search_rounded, color: _muted, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: tr('Tafuta dawa au aina'),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _ink),
          ),
        ),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: _q.text.isEmpty
              ? const SizedBox(width: 4)
              : IconButton(key: const ValueKey('x'), tooltip: tr('Futa'), icon: const Icon(Icons.close_rounded, size: 20, color: _muted), onPressed: _q.clear),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Semantics(
            button: true,
            label: tr('Skani'),
            excludeSemantics: true,
            child: Pressable(
              onTap: _scan,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 18, color: _primary),
                  const SizedBox(width: 6),
                  T('Skani', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _errorStrip() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFFDF1E3), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFF7A4A12)),
          const SizedBox(width: 8),
          Expanded(child: T('Inaonyesha hisa ya mara ya mwisho. Haikuweza kusasisha.', style: const TextStyle(fontSize: 13, color: Color(0xFF7A4A12)))),
          TextButton(onPressed: _load, child: const T('Jaribu tena')),
        ]),
      );

  Widget _errorFull() => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off_rounded, size: 40, color: _muted),
        const SizedBox(height: 12),
        Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: _ink)),
        const SizedBox(height: 16),
        Center(child: FilledButton(onPressed: _load, child: const T('Jaribu tena'))),
      ]);

  // ------------------------------------------------------------------ Orodha

  Widget _orodha() {
    final rows = _rows;
    final all = _all;
    final summary = ((_data ?? const {})['summary'] as Map?) ?? const {};
    final token = '$_filter|$_sort|$_cats|$_price|${_q.text}';
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey('stock-orodha'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _summary(summary, all)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _Pinned(
              height: 66,
              child: Container(color: _bg, padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: _searchField()),
            ),
          ),
          SliverToBoxAdapter(child: _filterBar(all, rows.length)),
          if (rows.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty(all.isEmpty))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _FadeIn(key: ValueKey('$token#${rows[i]['id']}'), index: i, child: _row(rows[i])),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(Map summary, List<Map<String, dynamic>> all) {
    Widget tile(String label, String value, {Color color = _ink, VoidCallback? onTap}) => Expanded(
          child: Pressable(
            onTap: onTap,
            haptic: onTap != null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: _muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color))),
              ]),
            ),
          ),
        );
    final value = asInt(summary['value_at_cost']);
    final reorder = asInt(summary['to_reorder']);
    final expiring = asInt(summary['expiring']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Row(children: [
        _costs ? tile(tr('Thamani'), value >= 1000000 ? 'TSh ${(value / 1000000).toStringAsFixed(2)}M' : formatTsh(value)) : tile(tr('Bidhaa'), '${all.length}'),
        const SizedBox(width: 8),
        tile(tr('Za kuagiza'), '$reorder', color: reorder > 0 ? const Color(0xFFA8321F) : _ink, onTap: () => _set('stock.filter', 'chache', (x) => _filter = x)),
        const SizedBox(width: 8),
        tile(tr('Inaisha muda'), '$expiring', color: expiring > 0 ? const Color(0xFF7A4A12) : _ink, onTap: () => _set('stock.filter', 'muda', (x) => _filter = x)),
      ]),
    );
  }

  static const _statusDefs = <(String, String, String?)>[
    ('zote', 'Zote', null),
    ('chache', 'Za kuagiza', 'low'),
    ('hazipo', 'Zimeisha', 'out'),
    ('muda', 'Muda', 'expiring'),
    ('zimeisha', 'Zimeisha muda', 'expired'),
    ('haina', 'Haina bei', null),
    ('mpya', 'Mpya · inasubiri mzigo', null),
  ];

  static const _sorts = <(String, String)>[('hali', 'Hali'), ('jina', 'Jina'), ('hisa', 'Hisa kidogo'), ('muda', 'Muda'), ('bei', 'Bei'), ('thamani', 'Thamani')];

  /// "Vichujio (n)" folds open into Aina (many), Hali, Bei and Panga; folded,
  /// what is chosen stays visible as tokens you can remove one by one.
  /// Counts follow each other: aisles within the status, statuses within the aisles.
  Widget _filterBar(List<Map<String, dynamic>> all, int shown) {
    final n = _activeFilters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            button: true,
            expanded: _panel,
            child: Pressable(
              onTap: () {
                tick();
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _panel = !_panel);
              },
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _panel || n > 0 ? _ink : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded, size: 17, color: _panel || n > 0 ? Colors.white : _ink),
                  const SizedBox(width: 7),
                  Text(n > 0 ? tr('Vichujio (:n)', {'n': n}) : tr('Vichujio'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _panel || n > 0 ? Colors.white : _ink)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _panel ? .5 : 0,
                    duration: Motion.of(context, Motion.fast),
                    child: Icon(Icons.expand_more_rounded, size: 18, color: _panel || n > 0 ? Colors.white : _ink),
                  ),
                ]),
              ),
            ),
          ),
          const Spacer(),
          Text(tr(':n kati ya :all', {'n': shown, 'all': all.length}), style: const TextStyle(fontSize: 13, color: _muted)),
        ]),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: _panel ? _panelBody(all, shown) : _tokens(),
        ),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: T(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5, color: _muted)),
      );

  Widget _panelBody(List<Map<String, dynamic>> all, int shown) {
    final cats = _catNames;
    final inStatus = all.where((p) => _match(p, _filter) && _inPrice(p)).toList();
    int catN(int c) => inStatus.where((p) => asInt(p['category_id']) == c).length;
    final inCats = all.where((p) => _inCats(p, _cats) && _inPrice(p)).toList();
    int stN(String f) => inCats.where((p) => _match(p, f)).length;
    Color? dotFor(String? look) => look == null ? null : stateLooks[look]!.color;
    final max = _priceMax;
    final range = _price ?? RangeValues(0, max);

    void toggleCat(int id) {
      tick();
      setState(() => _cats.contains(id) ? _cats.remove(id) : _cats.add(id));
      _saveFilters();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (cats.isNotEmpty || catN(0) > 0) ...[
          _label('AINA'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChipX(
              label: tr('Zote'),
              selected: _cats.isEmpty,
              count: inStatus.length,
              onTap: () {
                tick();
                setState(() => _cats = {});
                _saveFilters();
              },
            ),
            for (final e in cats.entries)
              if (catN(e.key) > 0 || _cats.contains(e.key))
                ChoiceChipX(label: e.value, selected: _cats.contains(e.key), count: catN(e.key), onTap: () => toggleCat(e.key)),
            if (catN(0) > 0 || _cats.contains(0))
              ChoiceChipX(label: tr('Bila aina'), selected: _cats.contains(0), count: catN(0), onTap: () => toggleCat(0)),
          ]),
        ],
        _label('HALI'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, label, look) in _statusDefs)
            // The rare ones (expired, no price, new) only when there are some.
            if (const ['zote', 'chache', 'hazipo', 'muda'].contains(k) || stN(k) > 0 || _filter == k)
              ChoiceChipX(
                label: tr(label),
                selected: _filter == k,
                count: stN(k),
                dot: dotFor(look),
                onTap: () {
                  tick();
                  setState(() => _filter = k);
                  _saveFilters();
                },
              ),
        ]),
        if (max > 0) ...[
          _label('BEI'),
          Row(children: [
            Text(formatTsh(range.start.round()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            Text(formatTsh(range.end.round()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: _primary, thumbColor: _primary, inactiveTrackColor: const Color(0xFFE3EAE7), overlayShape: SliderComponentShape.noOverlay),
            child: RangeSlider(
              values: RangeValues(range.start.clamp(0, max), range.end.clamp(0, max)),
              min: 0,
              max: max,
              divisions: 50,
              onChanged: (v) => setState(() => _price = (v.start <= 0 && v.end >= max) ? null : v),
              onChangeEnd: (_) => _saveFilters(),
            ),
          ),
        ],
        _label('PANGA'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, label) in _sorts)
            if (k != 'thamani' || _costs)
              ChoiceChipX(
                label: tr(label),
                selected: _sort == k,
                onTap: () {
                  tick();
                  setState(() => _sort = k);
                  _saveFilters();
                },
              ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          TextButton(
            onPressed: _activeFilters == 0 ? null : _clearAll,
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: const T('Futa vyote', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary, minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () {
                tick();
                setState(() => _panel = false);
              },
              child: Text(tr('Onyesha bidhaa :n', {'n': shown}), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Folded: one removable token per choice; nothing chosen, nothing shown.
  Widget _tokens() {
    final cats = _catNames;
    final status = _statusDefs.firstWhere((d) => d.$1 == _filter, orElse: () => _statusDefs.first);
    final sort = _sorts.firstWhere((d) => d.$1 == _sort, orElse: () => _sorts.first);
    final tokens = <(String, VoidCallback)>[
      for (final c in _cats) (c == 0 ? tr('Bila aina') : (cats[c] ?? '…'), () => _cats.remove(c)),
      if (_filter != 'zote') (tr(status.$2), () => _filter = 'zote'),
      if (_price != null) ('${shortTsh(_price!.start.round())} – ${shortTsh(_price!.end.round())}', () => _price = null),
      if (_sort != 'hali') (tr('Panga: :a', {'a': tr(sort.$2)}), () => _sort = 'hali'),
    ];
    if (tokens.isEmpty) return const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, remove) in tokens)
          Semantics(
            button: true,
            label: tr('Ondoa :a', {'a': label}),
            excludeSemantics: true,
            child: Pressable(
              onTap: () {
                tick();
                setState(remove);
                _saveFilters();
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.only(left: 12, right: 6),
                decoration: BoxDecoration(color: const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _primary)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.close_rounded, size: 16, color: _primary),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  String shortTsh(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K' : '$v';

  Widget _empty(bool nothingAtAll) {
    if (nothingAtAll) return Padding(padding: const EdgeInsets.only(bottom: 110), child: _emptyShop());
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 120),
      child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
        const PackIcon(form: 'other', color: Color(0xFFB8C4C0), size: 44, empty: true),
        const SizedBox(height: 14),
        const T('Hakuna bidhaa kwenye kichujio hiki.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            _q.clear();
            _clearAll();
          },
          child: const T('Onyesha zote'),
        ),
      ]),
    );
  }

  /// No products at all: the drawn empty shelves and the two ways to fill them.
  Widget _emptyShop() => EmptyShelves(actions: [
        if (_can(Perm.receive))
          FilledButton.icon(
            onPressed: () => _push(ReceiveScreen(session: widget.session)),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const T('Pokea mzigo'),
          ),
        if (_can(Perm.receive))
          OutlinedButton.icon(
            onPressed: () => _push(BulkEntryScreen(session: widget.session)),
            icon: const Icon(Icons.table_chart_outlined),
            label: const T('Ingiza hisa ya mwanzo'),
          ),
      ]);

  Widget _row(Map<String, dynamic> p) {
    final st = stateOf(p);
    final look = stateLooks[st]!;
    final out = p['is_out'] == true;
    final days = daysToExpiry(p);
    final cat = _catNames[asInt(p['category_id'])];
    final expText = p['is_expired'] == true
        ? tr('ina zilizoisha muda')
        : (days == null ? null : tr('inaisha :a', {'a': spanText(days)}));
    final expHot = p['is_expired'] == true || p['is_expiring'] == true;

    Widget tag(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        );

    final id = asInt(p['id']);
    final picked = _picked.contains(id);
    final inBasket = _inBasket.contains(id);
    final wants = out || p['is_low'] == true;

    final card = Semantics(
      button: true,
      label: '${p['name']}, ${tr(look.label)}, ${stockText(p)}',
      excludeSemantics: true,
      child: Pressable(
        onTap: _picked.isNotEmpty ? () => _togglePick(p) : () => _openProduct(p),
        onLongPress: _canOrder ? () => _togglePick(p) : null,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.curve,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFEAF6F0) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: picked ? const Color(0xFF8FD0B4) : Colors.transparent, width: 1.4),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // A coloured edge only on rows that need something.
              Container(width: 4, color: st == 'ok' ? Colors.transparent : look.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(children: [
                    // Picking several: a tick where the photo was.
                    if (_picked.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: AnimatedScale(
                          scale: picked ? 1 : .85,
                          duration: Motion.of(context, Motion.fast),
                          child: Icon(picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 24, color: picked ? _primary : const Color(0xFFB8C4C0)),
                        ),
                      ),
                    // The photo when there is one (v0.46.1), else the pack icon.
                    ProductThumb(
                      url: p['photo_url'] as String?,
                      fallback: Container(
                        decoration: BoxDecoration(color: out ? Colors.white : look.soft, borderRadius: BorderRadius.circular(12)),
                        child: Center(child: PackIcon(form: '${p['form'] ?? ''}', color: look.ink, size: 24, empty: out)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
                        const SizedBox(height: 5),
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (cat != null) tag(cat, const Color(0xFFEEF3F1), const Color(0xFF44564F)),
                          if (p['never_stocked'] == true) tag(tr('Mpya · inasubiri mzigo'), const Color(0xFFEAF0FD), const Color(0xFF2F5FC4))
                          else if (p['on_order'] == true) tag(tr('imeagizwa'), const Color(0xFFEAF0FD), const Color(0xFF2F5FC4)),
                          if (p['needs_price'] == true) tag(tr('Haina bei'), const Color(0xFFFDF1E3), const Color(0xFF7A4A12)),
                          if (expText != null)
                            Text(expText, style: TextStyle(fontSize: 12, color: expHot ? look.ink : _muted, fontWeight: expHot ? FontWeight.w700 : FontWeight.w500)),
                        ]),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: levelOf(p)),
                            duration: Motion.of(context, Motion.slow),
                            curve: Motion.curve,
                            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 5, backgroundColor: const Color(0xFFEEF3F1), color: look.color),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text(stockText(p), textAlign: TextAlign.right, maxLines: 2,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: out ? look.ink : _ink)),
                        const SizedBox(height: 4),
                        Text(mainPrice(p), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p['needs_price'] == true ? const Color(0xFF7A4A12) : _muted)),
                        if (_canOrder && _picked.isEmpty && (wants || inBasket)) ...[
                          const SizedBox(height: 8),
                          _orderPill(p, inBasket),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (!_canOrder || _picked.isNotEmpty) return card;
    // Swipe right: into the basket, and the row springs back.
    return Dismissible(
      key: ValueKey('basket-$id'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: .28},
      confirmDismiss: (_) async {
        inBasket ? await _fromBasket(p) : await _toBasket([p]);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(color: inBasket ? const Color(0xFFFBEDEA) : const Color(0xFFE3F4EC), borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(inBasket ? Icons.remove_shopping_cart_outlined : Icons.add_shopping_cart_rounded, color: inBasket ? const Color(0xFFB4503F) : _primary, size: 20),
          const SizedBox(width: 8),
          Text(inBasket ? tr('Toa kikapuni') : tr('Weka kikapuni'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: inBasket ? const Color(0xFFB4503F) : _primary)),
        ]),
      ),
      child: card,
    );
  }

  /// "Agiza" on what's out or low; "✓ Kikapuni" once it's in (tap to take out).
  Widget _orderPill(Map<String, dynamic> p, bool inBasket) => Pressable(
        onTap: () => inBasket ? _fromBasket(p) : _toBasket([p]),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.curve,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: inBasket ? const Color(0xFFE3F4EC) : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: inBasket ? const Color(0xFFBFE3D2) : _line),
          ),
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(a), child: c)),
            child: Row(key: ValueKey(inBasket), mainAxisSize: MainAxisSize.min, children: [
              Icon(inBasket ? Icons.check_rounded : Icons.add_shopping_cart_rounded, size: 14, color: _primary),
              const SizedBox(width: 4),
              Text(inBasket ? tr('Kikapuni') : tr('Agiza'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _primary)),
            ]),
          ),
        ),
      );

  /// Bottom: while picking, "n zimechaguliwa · Weka kikapuni"; otherwise the basket, when it has something.
  Widget _basketBar() {
    return ValueListenableBuilder<int>(
      valueListenable: OrderBasket.count,
      builder: (context, n, _) {
        final picking = _picked.isNotEmpty;
        final show = picking || n > 0;
        final rows = [for (final p in _all) if (_picked.contains(asInt(p['id']))) p];
        return AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.bottomCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.base),
                      switchInCurve: Motion.curve,
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(0, .35), end: Offset.zero).animate(a), child: c),
                      ),
                      child: picking
                          ? Container(
                              key: const ValueKey('pick'),
                              height: 56,
                              padding: const EdgeInsets.only(left: 6, right: 6),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99),
                                  boxShadow: [BoxShadow(color: const Color(0xFF0E3B31).withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 6))]),
                              child: Row(children: [
                                IconButton(
                                  tooltip: tr('Acha kuchagua'),
                                  onPressed: () => setState(_picked.clear),
                                  icon: const Icon(Icons.close_rounded, color: _muted),
                                ),
                                Expanded(
                                  child: Text(tr('Zimechaguliwa :n', {'n': _picked.length}),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _toBasket(rows),
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F8A6C), shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                  label: Text(tr('Weka kikapuni')),
                                ),
                              ]),
                            )
                          : Pressable(
                              key: const ValueKey('basket'),
                              onTap: _openBasket,
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.only(left: 8, right: 16),
                                decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(99),
                                    boxShadow: [BoxShadow(color: const Color(0xFF0E3B31).withValues(alpha: .22), blurRadius: 18, offset: const Offset(0, 6))]),
                                child: Row(children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), shape: BoxShape.circle),
                                    child: const Icon(Icons.shopping_basket_outlined, color: Color(0xFF3DDC97), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(tr('Kikapu cha kuagiza'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                      Text(tr('bidhaa :n', {'n': n}), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    ]),
                                  ),
                                  Text(tr('Fungua Agiza'), style: const TextStyle(color: Color(0xFF3DDC97), fontWeight: FontWeight.w800, fontSize: 13)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_rounded, color: Color(0xFF3DDC97), size: 18),
                                ]),
                              ),
                            ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// The search box and chips stay at the top while the list scrolls under them.
class _Pinned extends SliverPersistentHeaderDelegate {
  _Pinned({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_Pinned old) => true;
}

/// Rows settle in (fade + 6 px) when the filter, sort or search changes,
/// the first dozen a hair apart, so the change reads as one movement.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Duration(milliseconds: 180 + (index < 12 ? index * 22 : 0)));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: Motion.curve,
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 6), child: c)),
      child: child,
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Row(children: const [
          Expanded(child: Skeleton(height: 56, radius: 14)),
          SizedBox(width: 8),
          Expanded(child: Skeleton(height: 56, radius: 14)),
          SizedBox(width: 8),
          Expanded(child: Skeleton(height: 56, radius: 14)),
        ]),
        const SizedBox(height: 12),
        const Skeleton(height: 48, radius: 14),
        const SizedBox(height: 12),
        for (var i = 0; i < 7; i++) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Skeleton(width: 44, height: 44, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Skeleton(width: 120.0 + (i % 3) * 40, height: 14),
                  const SizedBox(height: 8),
                  const Skeleton(width: 90, height: 10),
                  const SizedBox(height: 8),
                  const Skeleton(height: 5),
                ]),
              ),
              const SizedBox(width: 12),
              const Skeleton(width: 56, height: 16),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
