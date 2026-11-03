import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'cart.dart';
import 'sell_unit.dart';

/// Scan at the counter, with the phone's own camera.
///
/// It stays open: scan, pick the unit (already chosen for you), add, scan the
/// next. The basket total shows at the top; "Maliza" goes back to pay.
///
/// An unknown code is asked about ONCE ("Ni bidhaa gani?") and then every
/// phone in the shop knows it. Nobody ever sits down to "enter barcodes".
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.api, required this.cart});

  final ApiClient api;
  final Cart cart;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [
    BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE,
    BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.dataMatrix, BarcodeFormat.qrCode,
  ]);

  bool _busy = false; // a sheet is open or a lookup is running: ignore the camera
  String? _lastCode;
  DateTime _lastAt = DateTime(2000);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    // The camera sees the same box many times a second: once per 2 seconds.
    if (code == _lastCode && DateTime.now().difference(_lastAt) < const Duration(seconds: 2)) return;
    _lastCode = code;
    _lastAt = DateTime.now();
    _busy = true;
    HapticFeedback.mediumImpact();
    try {
      final res = await widget.api.get('products/barcode/$code') as Map<String, dynamic>;
      if (!mounted) return;
      await _sellSheet(Product.fromJson(res), printedOn: res['barcode_unit'] as String?, usual: res['usual_unit'] as String?);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'unknown_barcode') {
        await _teach(code);
      } else {
        _toast(e.message, error: true);
      }
    } finally {
      _lastAt = DateTime.now(); // don't re-read the same box right after the sheet closes
      _busy = false;
    }
  }

  /// Known product: the unit is pre-chosen, the count is 1. Usually one tap.
  Future<void> _sellSheet(Product p, {String? printedOn, String? usual}) async {
    var unit = pickSellUnit(p, usual: usual, printedOn: printedOn);
    var qty = 1;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final max = Cart.maxOf(p, unit);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('Iliyopo: ${describeStock(p.onHand, p.units)}', style: const TextStyle(color: mutedText)),
                const SizedBox(height: 14),
                if (p.units.length > 1) ...[
                  const Text('Unauza nini?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final u in p.units)
                      ChoiceChip(
                        label: Text('${unitLabel(u.name)} · ${formatTsh(u.price)}'),
                        selected: u.sameAs(unit),
                        showCheckmark: false,
                        selectedColor: brandGreen,
                        labelStyle: TextStyle(color: u.sameAs(unit) ? Colors.white : inkColor, fontWeight: FontWeight.w700),
                        onSelected: (_) => setSheet(() {
                          unit = u;
                          qty = qty.clamp(1, Cart.maxOf(p, u).clamp(1, 1 << 30));
                        }),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  const Expanded(child: Text('Idadi', style: TextStyle(fontWeight: FontWeight.w800))),
                  IconButton.filledTonal(onPressed: qty > 1 ? () => setSheet(() => qty--) : null, icon: const Icon(Icons.remove)),
                  SizedBox(width: 48, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                  IconButton.filled(onPressed: qty < max ? () => setSheet(() => qty++) : null, icon: const Icon(Icons.add)),
                ]),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: max < 1
                      ? null
                      : () => Navigator.of(sheet).pop(widget.cart.addIn(p, unit, qty)),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: Text(max < 1
                      ? 'Hisa haitoshi'
                      : 'Ongeza $qty ${unitLabel(unit.name, qty)} · ${formatTsh(qty * unit.price)}'),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (added == true) {
      _toast('✓ ${p.name}: $qty ${unitLabel(unit.name, qty)}');
    } else if (added == false) {
      _toast('Hisa haitoshi: ${p.name}.', error: true);
    }
  }

  /// Unknown code: which product is it? Asked once, remembered for every phone.
  Future<void> _teach(String code) async {
    final picked = await showModalBottomSheet<(Product, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (_) => _TeachSheet(api: widget.api, code: code),
    );
    if (picked == null || !mounted) return;
    final (product, printedOn) = picked;
    try {
      await widget.api.post('products/${product.id}/barcodes', {'code': code, 'unit_name': ?printedOn});
      if (!mounted) return;
      _toast('Imeunganishwa. Ukiiskani tena, ${product.name} itajulikana yenyewe.');
      await _sellSheet(product, printedOn: printedOn);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? dangerRed : null,
        duration: const Duration(milliseconds: 1600),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: ListenableBuilder(
          listenable: widget.cart,
          builder: (context, _) => Text(
            widget.cart.isEmpty ? 'Skani barcode' : 'Kikapu · ${widget.cart.itemCount} · ${formatTsh(widget.cart.total)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          IconButton(tooltip: 'Tochi', onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined)),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Maliza', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // The aiming frame.
        Center(
          child: Container(
            width: 280,
            height: 170,
            decoration: BoxDecoration(border: Border.all(color: mintAccent, width: 3), borderRadius: BorderRadius.circular(22)),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Text(
            'Elekeza kwenye barcode: inasoma yenyewe.\nSkrini nyeusi? Ruhusu kamera: Settings › Afya Njia.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ]),
    );
  }
}

/// "Ni bidhaa gani?": search the shop's products, pick one, and say what the
/// code is printed on (the box, the strip...). Returns (product, unit name).
class _TeachSheet extends StatefulWidget {
  const _TeachSheet({required this.api, required this.code});

  final ApiClient api;
  final String code;

  @override
  State<_TeachSheet> createState() => _TeachSheetState();
}

class _TeachSheetState extends State<_TeachSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Product> _results = [];
  Product? _product;
  String? _printedOn;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) return;
      try {
        final data = await widget.api.get('products', query: {'q': q.trim()}) as List;
        if (mounted && q == _q.text) setState(() => _results = data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList());
      } on ApiException {
        // keep the old list
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('BARCODE MPYA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: warnAmber, letterSpacing: 0.4)),
          const Text('Ni bidhaa gani?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const Text('Chagua mara moja tu. Ukiiskani tena itajulikana yenyewe.', style: TextStyle(color: mutedText)),
          const SizedBox(height: 12),
          if (p == null) ...[
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(labelText: 'Tafuta dawa', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            for (final r in _results.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Iliyopo: ${describeStock(r.onHand, r.units)}'),
                trailing: const Text('Unganisha', style: TextStyle(color: brandGreen, fontWeight: FontWeight.w800)),
                onTap: () => setState(() {
                  _product = r;
                  // Barcodes are mostly on the outer pack.
                  _printedOn = r.units.length > 1 ? r.units.last.name : r.units.first.name;
                }),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Haipo kabisa? Iongeze kwanza kupitia Pokea mzigo.', style: TextStyle(fontSize: 12, color: mutedText)),
            ),
          ] else ...[
            Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('Barcode iko kwenye nini?', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final u in p.units)
                ChoiceChip(
                  label: Text(unitLabel(u.name)),
                  selected: _printedOn == u.name,
                  showCheckmark: false,
                  selectedColor: brandGreen,
                  labelStyle: TextStyle(color: _printedOn == u.name ? Colors.white : inkColor, fontWeight: FontWeight.w700),
                  onSelected: (_) => setState(() => _printedOn = u.name),
                ),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((p, _printedOn)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: const Text('Unganisha'),
            ),
            TextButton(onPressed: () => setState(() => _product = null), child: const Text('Si hii, rudi')),
          ],
        ]),
      ),
    );
  }
}
