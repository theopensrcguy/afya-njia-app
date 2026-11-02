import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'cart.dart';
import 'checkout_screen.dart';
import 'quantity_dialog.dart';

/// Screen 2 of the mockups: search and add to the basket.
///
/// The search results get the whole screen; the basket is a slim bar at the
/// bottom ("Kikapu · 2 bidhaa · TSh 600 · Lipa"). Tapping it opens the checkout
/// screen. (The first version put the whole basket here, and with the keyboard
/// open there was no room left to see the results.)
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

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    // Show the catalog straight away. Wait for the first frame: setState()
    // is not allowed while the screen is still being created.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    // Anything that keeps running (timers, controllers, notifiers) must be
    // stopped when the screen closes, or it leaks memory.
    _debounce?.cancel();
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

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final data = await _api.get('products', query: {'q': query.trim()}) as List<dynamic>;
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
      _showMessage('Tuma mauzo yaliyopita kwanza ("Tuma tena").', isError: true);
      return;
    }
    if (_cart.add(product)) {
      HapticFeedback.selectionClick(); // feel the tap without looking up
    } else {
      _showMessage('Hisa haitoshi: ${product.name} (zilizopo ${describeStock(product.onHand, product.units)}).', isError: true);
    }
  }

  void _changeUnit(Product p, ProductUnit unit) {
    if (!_cart.setUnit(p.id, unit)) {
      _showMessage('Hakuna ${unitLabel(unit.name)} nzima ya ${p.name} (zilizopo ${describeStock(p.onHand, p.units)}).', isError: true);
    }
  }

  Future<void> _openCheckout() async {
    FocusScope.of(context).unfocus(); // close the keyboard first
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CheckoutScreen(api: _api, cart: _cart)),
    );
    if (!mounted) return;
    // Stock changed after a sale (or a stock error at checkout): refresh the numbers.
    if (completed == true) _searchController.clear();
    _search(_searchController.text);
  }

  /// Leaving with items in the basket would lose them: ask first.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Toka kwenye mauzo?'),
        content: Text('Kikapu kina bidhaa ${_cart.itemCount}. Zitaondolewa.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hapana')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Toka')),
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
            const Text('Mauzo mapya', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Mhudumu: $userName', style: const TextStyle(fontSize: 12, color: mutedText)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Tafuta dawa',
                hintText: 'Andika jina au barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Futa',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              _search('');
                            },
                          ),
              ),
            ),
          ),
          // The results also listen to the cart, to show "×2" on items already in it.
          Expanded(child: ListenableBuilder(listenable: _cart, builder: (context, _) => _buildResults())),
          ListenableBuilder(listenable: _cart, builder: (context, _) => _buildCartBar()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_searchError!, textAlign: TextAlign.center),
            TextButton(onPressed: () => _search(_searchController.text), child: const Text('Jaribu tena')),
          ],
        ),
      );
    }
    if (_results.isEmpty && !_searching) {
      return const Center(child: Text('Hakuna bidhaa iliyopatikana.'));
    }

    // The server sends only suggestions, or only real matches, never a mix.
    // Suggestions get a heading so the helper knows the spelling didn't match
    // and checks the name before tapping. (Look-alike medicines exist:
    // tapping must be a conscious choice, never automatic.)
    final suggesting = _results.isNotEmpty && _results.every((p) => p.suggested);
    final offset = suggesting ? 1 : 0;

    return ListView.separated(
      // Scrolling the results closes the keyboard, so the whole list is visible.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length + offset,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (suggesting && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Hakuna "${_searchController.text.trim()}". '),
                const TextSpan(text: 'Je, ulimaanisha…?', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              style: const TextStyle(color: warnAmber, fontSize: 14),
            ),
          );
        }
        final p = _results[i - offset];
        final outOfStock = p.onHand == 0;
        final stockText = outOfStock
            ? 'Hazipo (zimeisha)'
            : 'Hisa: ${describeStock(p.onHand, p.units)}${p.lowStock ? ' · chini' : ''}'
                '${p.nextExpiry != null ? ' · inaisha ${_monthYear(p.nextExpiry!)}' : ''}';

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
            onTap: outOfStock ? null : () => _addToCart(p),
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
          tooltip: quantity == 1 ? 'Ondoa' : 'Punguza',
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
          tooltip: 'Ongeza',
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
      _showMessage('Hisa haitoshi: ${p.name} (zilizopo ${describeStock(p.onHand, p.units)}).', isError: true);
    }
  }

  /// One slim bar: how many items, the total, and "Lipa". About 64 points
  /// high, so the results keep the screen even with the keyboard open.
  Widget _buildCartBar() {
    if (_cart.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: _openCheckout,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.shopping_basket_outlined, color: brandGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kikapu · ${_cart.itemCount} bidhaa', style: const TextStyle(fontSize: 12, color: mutedText)),
                      Text(formatTsh(_cart.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _openCheckout,
                  style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_cart.uncertain ? 'Tuma tena' : 'Lipa', style: const TextStyle(fontSize: 16)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];
  String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
}
