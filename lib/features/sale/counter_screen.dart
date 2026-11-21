import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'cart.dart';
import 'checkout_screen.dart';
import 'quantity_dialog.dart';
import 'scan_screen.dart';
import 'sell_unit.dart';
import '../../core/i18n.dart';

/// Screen 2 of the mockups: search and add to the basket.
///
/// v0.45.3: one scroll. Aina chips, the Haraka tiles and the products scroll
/// together, so the tiles never hold half the screen; once they scroll out of
/// sight a slim Haraka strip appears under the search, and its ↑ brings the
/// tiles back. The tiles can also be folded away (remembered). The basket
/// floats at the bottom; tapping it opens the checkout as a sheet over this
/// screen, which slides down again ("Endelea kuchagua") to keep adding.
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key, required this.session});

  final Session session;

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  final _cart = Cart();
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Product> _results = [];
  bool _searching = false;
  String? _searchError;

  /// The Haraka tiles: (product, the unit it usually sells in).
  List<(Product, String?)> _haraka = [];

  /// Aina (shelves): Dawa, Mama na mtoto, Vipodozi… With the search box empty,
  /// tapping one lists that shelf's products. null = Haraka + everything.
  List<Map<String, dynamic>> _shelves = [];
  int _unsorted = 0;
  String? _shelf;
  String? _part; // asubuhi | mchana | jioni

  final _scroll = ScrollController();
  final _harakaKey = GlobalKey();
  bool _strip = false; // the tiles have scrolled away: show the slim strip
  bool _harakaOpen = UiMemory.get('counter.haraka', true);

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    // Deni (credit) is a way to pay only for someone allowed to sell on credit.
    _cart.creditAllowed = widget.session.user!.can(Perm.sellOnCredit);
    // Show the catalog straight away. Wait for the first frame: setState()
    // is not allowed while the screen is still being created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _search('');
      _loadHaraka();
      _loadShelves();
    });
  }

  /// What sells most at this time of day. Optional: without it the counter
  /// works as before (an older server, no sales yet, no network).
  Future<void> _loadHaraka() async {
    try {
      final res = await _api.get('products/haraka') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _part = res['part'] as String?;
        _haraka = [
          for (final e in ((res['products'] as List?) ?? const []).cast<Map<String, dynamic>>())
            (Product.fromJson(e), e['usual_unit'] as String?),
        ];
      });
    } on ApiException {
      // no tiles, nothing lost
    }
  }

  void _tapTile(Product p, String? usual) {
    if (!_cart.canEdit) {
      _showMessage(tr('Tuma mauzo yaliyopita kwanza ("Tuma tena").'), isError: true);
      return;
    }
    // Same unit as already in the basket, or the usual one.
    final unit = _cart.unitOf(p.id) ?? pickSellUnit(p, usual: usual);
    if (_cart.addIn(p, unit)) {
      HapticFeedback.selectionClick();
    } else {
      _showMessage(tr('Hisa haitoshi: :name (zilizopo :a).', {'name': p.name, 'a': describeStock(p.onHand, p.units)}), isError: true);
    }
  }

  Future<void> _openScanner() async {
    FocusScope.of(context).unfocus();
    if (!_cart.canEdit) {
      _showMessage(tr('Tuma mauzo yaliyopita kwanza ("Tuma tena").'), isError: true);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanScreen(api: _api, cart: _cart)));
  }

  @override
  void dispose() {
    // Anything that keeps running (timers, controllers, notifiers) must be
    // stopped when the screen closes, or it leaks memory.
    _debounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    _cart.dispose();
    super.dispose();
  }

  /// Debounce: wait until typing pauses for 300 ms before calling the server.
  /// Typing "amoxicillin" would otherwise send 11 requests.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _loadShelves() async {
    try {
      final r = await _api.get('product-categories') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _shelves = (r['categories'] as List).cast<Map<String, dynamic>>().where((c) => ((c['products'] as num?) ?? 0) > 0).toList();
        _unsorted = (r['unsorted'] as num?)?.toInt() ?? 0;
      });
    } on ApiException {
      // No shelves: the counter works as before.
    }
  }

  /// Tapping the chosen shelf again goes back to everything.
  void _pickShelf(String? id) {
    tick();
    setState(() => _shelf = _shelf == id ? null : id);
    _search('');
  }

  bool get _showHaraka => _searchController.text.trim().isEmpty && _shelf == null && _haraka.isNotEmpty;

  /// Shows the slim strip once the tiles are out of sight.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final box = _harakaKey.currentContext?.findRenderObject() as RenderBox?;
    final h = (box?.hasSize ?? false) ? box!.size.height : 0.0;
    final show = _showHaraka && _harakaOpen && h > 0 && n.metrics.pixels > h + 30;
    if (show != _strip) setState(() => _strip = show);
    return false;
  }

  Widget _buildShelves() {
    final chips = <(String?, String)>[
      (null, tr('Zote')),
      for (final c in _shelves) ('${c['id']}', '${c['name']}'),
      if (_unsorted > 0) ('none', tr('Haijapangwa')),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: [
          for (final (id, label) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChipX(label: label, selected: _shelf == id, onTap: () => _pickShelf(id)),
            ),
        ],
      ),
    );
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final data = await _api.get('products', query: {
        'q': query.trim(),
        // A shelf only while the box is empty: typing searches everything.
        if (query.trim().isEmpty && _shelf != null) 'category': _shelf!,
      }) as List<dynamic>;
      if (!mounted) return;
      // Ignore late answers for an old query (the user kept typing).
      if (query != _searchController.text) return;
      setState(() => _results = data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addToCart(Product product) {
    if (!_cart.canEdit) {
      _showMessage(tr('Tuma mauzo yaliyopita kwanza ("Tuma tena").'), isError: true);
      return;
    }
    if (_cart.add(product)) {
      HapticFeedback.selectionClick(); // feel the tap without looking up
    } else {
      _showMessage(tr('Hisa haitoshi: :name (zilizopo :a).', {'name': product.name, 'a': describeStock(product.onHand, product.units)}), isError: true);
    }
  }

  /// Wanaouliza (v0.48): a customer asked and we had none. One tap; a phone
  /// number only if they want a call when it comes. Agiza shows it.
  Future<void> _asked({Product? product, String? name}) async {
    final what = product?.name ?? name ?? '';
    if (what.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final phone = TextEditingController();
    final who = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Mteja ameulizia :a', {'a': what}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const T('Itaonekana kwenye Agiza → Wanaouliza. Akitaka apigiwe ikifika, weka namba yake.', style: TextStyle(fontSize: 13, color: mutedText)),
            const SizedBox(height: 14),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('Simu ya mteja (si lazima)'), prefixIcon: const Icon(Icons.call_outlined)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: who,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Jina (si lazima)'), prefixIcon: const Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheet).pop(true),
              icon: const Icon(Icons.campaign_outlined),
              label: const T('Andika'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await _api.post('product-requests', {
        if (product != null) 'product_id': product.id else 'name': what.trim(),
        if (phone.text.trim().isNotEmpty) 'customer_phone': phone.text.trim(),
        if (who.text.trim().isNotEmpty) 'customer_name': who.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _showMessage(asIntOr(r['asked']) > 1
          ? tr('Imeandikwa. Wateja :n wameulizia :a.', {'n': r['asked'], 'a': what})
          : tr('Imeandikwa: :a. Itaonekana kwenye Agiza.', {'a': what}));
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message, isError: true);
    }
  }

  static int asIntOr(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// "Haipo? Mteja ameulizia": under results that aren't what was asked for.
  Widget _askedButton(String typed) => TextButton.icon(
        onPressed: () => _asked(name: typed),
        icon: const Icon(Icons.campaign_outlined, size: 18),
        label: Text(tr('Mteja ameulizia ":a"', {'a': typed}), maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  void _changeUnit(Product p, ProductUnit unit) {
    if (!_cart.setUnit(p.id, unit)) {
      _showMessage(tr('Hakuna :a nzima ya :name (zilizopo :b).', {'a': unitLabel(unit.name), 'name': p.name, 'b': describeStock(p.onHand, p.units)}), isError: true);
    }
  }

  Future<void> _openCheckout() async {
    FocusScope.of(context).unfocus(); // close the keyboard first
    final completed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: CheckoutScreen(api: _api, cart: _cart, canApproveCredit: widget.session.user!.can(Perm.manageCredit), asSheet: true),
        ),
      ),
    );
    if (!mounted) return;
    // Stock changed after a sale (or a stock error at checkout): refresh the numbers.
    if (completed == true) _searchController.clear();
    _search(_searchController.text);
    _loadHaraka(); // stock changed; tiles skip what's run out
  }

  /// Leaving with items in the basket would lose them: ask first.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const T('Toka kwenye mauzo?'),
        content: Text(tr('Kikapu kina bidhaa :item_count. Zitaondolewa.', {'item_count': _cart.itemCount})),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const T('Hapana')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const T('Toka')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _cart.clear();
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;

    return ListenableBuilder(
      listenable: _cart,
      builder: (context, child) => PopScope(
        canPop: _cart.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: child!,
      ),
      // The Scaffold is passed as `child`, so it is NOT rebuilt when the cart
      // changes; only the small PopScope wrapper is.
      child: _buildScaffold(user.name),
    );
  }

  Widget _buildScaffold(String userName) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const T('Mauzo mapya', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(tr('Mhudumu: :user_name', {'user_name': userName}), style: const TextStyle(fontSize: 12, color: mutedText)),
          ],
        ),
      ),
      body: Stack(children: [
        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: tr('Tafuta dawa'),
                hintText: tr('Andika jina au barcode'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _searchController.text.isEmpty
                        ? IconButton(
                            tooltip: tr('Skani barcode'),
                            icon: const Icon(Icons.qr_code_scanner, color: brandGreen),
                            onPressed: _openScanner,
                          )
                        : IconButton(
                            tooltip: tr('Futa'),
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              _search('');
                            },
                          ),
              ),
            ),
          ),
          // Tiles scrolled away: the same products as one slim strip.
          ListenableBuilder(
            listenable: _cart,
            builder: (context, _) => AnimatedSize(
              duration: Motion.of(context, Motion.base),
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: _strip && _showHaraka ? _harakaStrip() : const SizedBox(width: double.infinity),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _cart,
              builder: (context, _) => NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    if (_searchController.text.trim().isEmpty && _shelves.isNotEmpty) SliverToBoxAdapter(child: _buildShelves()),
                    if (_showHaraka) SliverToBoxAdapter(child: KeyedSubtree(key: _harakaKey, child: _buildHaraka())),
                    ..._buildResults(),
                    // Room under the last product for the floating basket.
                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
              ),
            ),
          ),
        ]),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ListenableBuilder(listenable: _cart, builder: (context, _) => _buildCartBar()),
        ),
      ]),
    );
  }

  List<Widget> _buildResults() {
    if (_searchError != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_searchError!, textAlign: TextAlign.center),
                TextButton(onPressed: () => _search(_searchController.text), child: const T('Jaribu tena')),
              ],
            ),
          ),
        ),
      ];
    }
    if (_results.isEmpty && !_searching) {
      final typed = _searchController.text.trim();
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const T('Hakuna bidhaa iliyopatikana.'),
              if (typed.isNotEmpty) ...[const SizedBox(height: 6), _askedButton(typed)],
            ]),
          ),
        ),
      ];
    }

    // The server sends only suggestions, or only real matches, never a mix.
    // Suggestions get a heading so the helper knows the spelling didn't match
    // and checks the name before tapping. (Look-alike medicines exist:
    // tapping must be a conscious choice, never automatic.)
    final suggesting = _results.isNotEmpty && _results.every((p) => p.suggested);
    final offset = suggesting ? 1 : 0;

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
      itemCount: _results.length + offset + (suggesting ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (suggesting && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: tr('Hakuna ":a". ', {'a': _searchController.text.trim()})),
                TextSpan(text: tr('Je, ulimaanisha…?'), style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              style: const TextStyle(color: warnAmber, fontSize: 14),
            ),
          );
        }
        if (suggesting && i == _results.length + offset) {
          return Align(alignment: Alignment.centerLeft, child: _askedButton(_searchController.text.trim()));
        }
        final p = _results[i - offset];
        final outOfStock = p.onHand == 0;
        final stockText = outOfStock
            ? tr('Zimeisha · gusa: mteja ameulizia')
            : '${tr('Hisa: :a:b', {'a': describeStock(p.onHand, p.units), 'b': p.lowStock ? tr(' · chini') : ''})}'
                '${p.nextExpiry != null ? tr(' · inaisha :a', {'a': _monthYear(p.nextExpiry!)}) : ''}';

        final inBasket = _cart.quantityOf(p.id);
        // The price shown is for the unit being sold (or the one a tap would add).
        final unit = _cart.unitOf(p.id) ?? p.defaultUnit;

        return Material(
          color: Colors.white,
          // A thin amber border marks a suggestion, so it never looks like an exact match.
          // A green border marks an item already in the basket.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: p.suggested
                ? const BorderSide(color: warnAmber)
                : inBasket > 0
                    ? const BorderSide(color: brandGreen)
                    : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Out: one tap writes down that a customer asked (Wanaouliza).
            onTap: outOfStock ? () => _asked(product: p) : () => _addToCart(p),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.name,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: outOfStock ? mutedText : inkColor)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('${formatTsh(unit.price)} / ${unitLabel(unit.name)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stockText,
                          style: TextStyle(color: outOfStock ? dangerRed : (p.lowStock ? warnAmber : mutedText)),
                        ),
                      ),
                      // In the basket: change the amount right here. The list
                      // never re-orders, so the next tap always lands on the
                      // same medicine.
                      if (inBasket > 0) _stepper(p, inBasket),
                    ],
                  ),
                  // In the basket and sold in more than one way: pick kidonge / kadi / boksi.
                  if (inBasket > 0 && p.units.length > 1) _unitChips(p, unit),
                ],
              ),
            ),
          ),
        );
      },
        ),
      ),
    ];
  }

  static const _parts = {'asubuhi': 'asubuhi', 'mchana': 'mchana', 'jioni': 'jioni'};

  /// Up to 9 one-tap tiles: one tap = one of the usual unit. Hold for an exact number.
  Widget _buildHaraka() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The header folds the tiles away (and back); remembered while the app is open.
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            tick();
            setState(() => _harakaOpen = !_harakaOpen);
            UiMemory.set('counter.haraka', _harakaOpen);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const T('Haraka', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('zinazouzwa sana :a', {'a': tr(_parts[_part] ?? 'sasa')}),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
              ),
              Text(_harakaOpen ? tr('Ficha') : tr('Onyesha'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: brandGreen)),
              AnimatedRotation(
                turns: _harakaOpen ? .5 : 0,
                duration: Motion.of(context, Motion.fast),
                child: const Icon(Icons.expand_more_rounded, size: 20, color: brandGreen),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: !_harakaOpen
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // A fixed height that grows with the phone's text size (Settings ›
          // Display › Text Size), instead of a width:height ratio: with bigger
          // text, a ratio left the price no room ("overflowed by 1.8 pixels").
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: MediaQuery.textScalerOf(context).scale(96),
          ),
          children: [
            for (final (p, usual) in _haraka)
              Builder(builder: (context) {
                final unit = _cart.unitOf(p.id) ?? pickSellUnit(p, usual: usual);
                final n = _cart.quantityOf(p.id);
                return Material(
                  color: n > 0 ? const Color(0xFFDDF3EA) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _tapTile(p, usual),
                    onLongPress: () async {
                      if (n == 0) _tapTile(p, usual);
                      if (_cart.quantityOf(p.id) > 0) await _typeQuantity(p, _cart.quantityOf(p.id));
                    },
                    child: Stack(children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.2)),
                          const Spacer(),
                          Text(unitLabel(unit.name), style: const TextStyle(fontSize: 11, color: mutedText, fontWeight: FontWeight.w700)),
                          Text(formatTsh(unit.price), style: const TextStyle(fontSize: 13, color: brandGreen, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      if (n > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            height: 24,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(12)),
                            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ]),
                  ),
                );
              }),
          ],
        ),
                ),
        ),
      ]),
    );
  }

  /// The tiles as one slim row while they're scrolled out of sight. ↑ goes back to them.
  Widget _harakaStrip() {
    return Container(
      height: 46,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE3EAE7)))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        children: [
          IconButton(
            tooltip: tr('Rudi juu'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _scroll.animateTo(0, duration: Motion.of(context, Motion.base), curve: Motion.curve),
            icon: const Icon(Icons.keyboard_arrow_up_rounded, color: brandGreen),
          ),
          for (final (p, usual) in _haraka)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Builder(builder: (context) {
                final n = _cart.quantityOf(p.id);
                return Pressable(
                  onTap: () => _tapTile(p, usual),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: n > 0 ? const Color(0xFFDDF3EA) : Colors.white, borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                      if (n > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(99)),
                          child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ],
                    ]),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  /// [Kidonge 50] [Kadi 500] [Boksi 4,500]: each unit with its own price.
  Widget _unitChips(Product p, ProductUnit current) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final u in p.units)
            ChoiceChip(
              label: Text('${unitLabel(u.name)} · ${formatTsh(u.price)}'),
              selected: u.sameAs(current),
              selectedColor: mintSoft,
              showCheckmark: false,
              labelStyle: TextStyle(fontWeight: u.sameAs(current) ? FontWeight.w800 : FontWeight.w500),
              onSelected: _cart.canEdit ? (_) => _changeUnit(p, u) : null,
            ),
        ],
      ),
    );
  }

  /// − [21] +   The number opens a keypad to type an exact amount.
  Widget _stepper(Product p, int quantity) {
    const box = BoxConstraints.tightFor(width: 40, height: 40); // big enough for a thumb
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: quantity == 1 ? tr('Ondoa') : tr('Punguza'),
          constraints: box,
          padding: EdgeInsets.zero,
          onPressed: _cart.canEdit ? () => _cart.setQuantity(p.id, quantity - 1) : null,
          icon: Icon(quantity == 1 ? Icons.delete_outline : Icons.remove_circle_outline, color: brandGreen),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _cart.canEdit ? () => _typeQuantity(p, quantity) : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: const Color(0xFFE7F1EC), borderRadius: BorderRadius.circular(8)),
            child: Text('$quantity', style: const TextStyle(color: brandGreen, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        IconButton(
          tooltip: tr('Ongeza'),
          constraints: box,
          padding: EdgeInsets.zero,
          onPressed: _cart.canEdit ? () => _addToCart(p) : null,
          icon: const Icon(Icons.add_circle_outline, color: brandGreen),
        ),
      ],
    );
  }

  Future<void> _typeQuantity(Product p, int current) async {
    final value = await askQuantity(context, p, current, unit: _cart.unitOf(p.id));
    if (value == null || !mounted) return;
    if (!_cart.setQuantity(p.id, value)) {
      _showMessage(tr('Hisa haitoshi: :name (zilizopo :a).', {'name': p.name, 'a': describeStock(p.onHand, p.units)}), isError: true);
    }
  }

  /// The basket floats over the list: a dark pill with the count, the total
  /// and "Lipa". It slides in with the first item.
  Widget _buildCartBar() {
    final empty = _cart.isEmpty;
    return IgnorePointer(
      ignoring: empty,
      child: AnimatedSlide(
        offset: empty ? const Offset(0, 1.4) : Offset.zero,
        duration: Motion.of(context, Motion.base),
        curve: Motion.curve,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: const Color(0xFF14211D),
            borderRadius: BorderRadius.circular(24),
            elevation: 10,
            shadowColor: const Color(0x55142A23),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: empty ? null : _openCheckout,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: Row(children: [
                  Badge(
                    label: Text('${_cart.itemCount}'),
                    backgroundColor: const Color(0xFF3DDC97),
                    textColor: const Color(0xFF0E3B31),
                    child: const Icon(Icons.shopping_basket_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Kikapu · :item_count bidhaa', {'item_count': _cart.itemCount}), style: const TextStyle(fontSize: 12, color: Color(0xFFB7C7C1))),
                      CountUp(value: _cart.total, format: formatTsh, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                  FilledButton(
                    onPressed: empty ? null : _openCheckout,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3DDC97),
                      foregroundColor: const Color(0xFF0E3B31),
                      minimumSize: const Size(104, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_cart.uncertain ? tr('Tuma tena') : tr('Lipa'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];
  String _monthYear(DateTime d) => '${tr(_months[d.month - 1])} ${d.year}';
}
