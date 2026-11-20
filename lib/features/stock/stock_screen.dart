import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/scan_once.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
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
  const StockScreen({super.key, required this.session, this.initialFilter});

  final Session session;

  /// zote | chache | hazipo | muda | zimeisha | haina | mpya. Given by home's
  /// "Fungua orodha: …"; otherwise the last one used.
  final String? initialFilter;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _q.addListener(() => setState(() {}));
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

  List<Map<String, dynamic>> get _rows {
    final q = _q.text.trim().toLowerCase();
    final cats = _catNames;
    final rows = _all.where((p) {
      if (!_match(p, _filter)) return false;
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
      floatingActionButton: !_can(Perm.receive)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _push(ReceiveScreen(session: widget.session)),
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              isExtended: _fabWide,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const T('Pokea mzigo'),
            ),
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
                            child: RafuView(
                              products: _all,
                              categories: _catNames,
                              mode: _rafuMode,
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
        // Rafu colours by stock or by expiry; shown only on Rafu.
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: _view != 'rafu'
              ? const SizedBox.shrink()
              : SizedBox(
                  key: const ValueKey('mode'),
                  width: 132,
                  child: SlidingSegments<String>(
                    values: const ['hisa', 'muda'],
                    labels: [tr('Hisa'), tr('Muda')],
                    selected: _rafuMode,
                    height: 36,
                    fontSize: 13,
                    onChanged: (v) => _set('stock.rafuMode', v, (x) => _rafuMode = x),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (_can(Perm.countStock) || _can(Perm.adjustStock)) ...[
          _square(Icons.fact_check_outlined, tr('Hesabu ya hisa'), () => _push(StockCountScreen(session: widget.session))),
          const SizedBox(width: 8),
        ],
        _square(Icons.delete_sweep_outlined, tr('Maombi ya kufuta hisa'), () => _push(DeletionsScreen(session: widget.session)), badge: _deletions),
      ]),
    );
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
        Container(width: 1, height: 22, color: const Color(0xFFE3EAE7)),
        IconButton(tooltip: tr('Skani'), icon: const Icon(Icons.qr_code_scanner_rounded, color: _ink), onPressed: _scan),
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
    final token = '$_filter|$_sort|${_q.text}';
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
              height: 116,
              child: Container(
                color: _bg,
                padding: const EdgeInsets.fromLTRB(16, 8, 0, 10),
                child: Column(children: [
                  Padding(padding: const EdgeInsets.only(right: 16), child: _searchField()),
                  const SizedBox(height: 10),
                  SizedBox(height: 38, child: _chips(all)),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Text(tr(':n kati ya :all', {'n': rows.length, 'all': all.length}), style: const TextStyle(fontSize: 13, color: _muted)),
                ),
                TextButton.icon(
                  onPressed: _pickSort,
                  icon: const Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text(tr('Panga: :a', {'a': tr(_sortLabels[_sort] ?? 'Hali')})),
                  style: TextButton.styleFrom(foregroundColor: _primary, textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
            ),
          ),
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

  static const _sortLabels = {'hali': 'Hali', 'jina': 'Jina', 'hisa': 'Hisa', 'muda': 'Muda', 'thamani': 'Thamani'};

  Future<void> _pickSort() async {
    final options = [
      ('hali', 'Hali', 'Zinazohitaji kitu kwanza'),
      ('jina', 'Jina', 'A mpaka Z'),
      ('hisa', 'Hisa', 'Kidogo kwanza'),
      ('muda', 'Muda', 'Zinazoisha muda karibu kwanza'),
      if (_costs) ('thamani', 'Thamani', 'Pesa nyingi kwanza'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, label, sub) in options)
            ListTile(
              title: T(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: T(sub),
              trailing: _sort == k ? const Icon(Icons.check_rounded, color: _primary) : null,
              onTap: () => Navigator.of(sheet).pop(k),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) {
      tick();
      _set('stock.sort', picked, (x) => _sort = x);
    }
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

  Widget _chips(List<Map<String, dynamic>> all) {
    int n(String f) => all.where((p) => _match(p, f)).length;
    final defs = <(String, String, Color?)>[
      ('zote', 'Zote', null),
      ('chache', 'Za kuagiza', stateLooks['low']!.color),
      ('hazipo', 'Zimeisha', stateLooks['out']!.color),
      ('muda', 'Muda', stateLooks['expiring']!.color),
      if (n('zimeisha') > 0 || _filter == 'zimeisha') ('zimeisha', 'Zimeisha muda', stateLooks['expired']!.color),
      if (n('haina') > 0 || _filter == 'haina') ('haina', 'Haina bei', const Color(0xFF9A5B0F)),
      if (n('mpya') > 0 || _filter == 'mpya') ('mpya', 'Mpya', const Color(0xFF2F5FC4)),
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      itemCount: defs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final (k, label, dot) = defs[i];
        return ChoiceChipX(
          label: tr(label),
          dot: dot,
          count: n(k),
          selected: _filter == k,
          onTap: () => _set('stock.filter', k, (x) => _filter = x),
        );
      },
    );
  }

  Widget _empty(bool nothingAtAll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 120),
      child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
        const PackIcon(form: 'other', color: Color(0xFFB8C4C0), size: 44, empty: true),
        const SizedBox(height: 14),
        T(nothingAtAll ? 'Bado hakuna bidhaa dukani.' : 'Hakuna bidhaa kwenye kichujio hiki.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
        const SizedBox(height: 12),
        if (nothingAtAll && _can(Perm.receive))
          FilledButton.icon(
            onPressed: () => _push(ReceiveScreen(session: widget.session)),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const T('Pokea mzigo wa kwanza'),
          )
        else if (!nothingAtAll)
          OutlinedButton(
            onPressed: () {
              _q.clear();
              _set('stock.filter', 'zote', (x) => _filter = x);
            },
            child: const T('Onyesha zote'),
          ),
      ]),
    );
  }

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

    return Semantics(
      button: true,
      label: '${p['name']}, ${tr(look.label)}, ${stockText(p)}',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => _openProduct(p),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // A coloured edge only on rows that need something.
              Container(width: 4, color: st == 'ok' ? Colors.transparent : look.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: out ? Colors.white : look.soft, borderRadius: BorderRadius.circular(12)),
                      child: Center(child: PackIcon(form: '${p['form'] ?? ''}', color: look.ink, size: 24, empty: out)),
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
