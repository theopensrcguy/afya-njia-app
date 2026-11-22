import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client.dart';
import 'dialogs.dart';
import 'i18n.dart';

/// Barcode helpers (v0.48.5): scan one code, and link a code to a product
/// in a way that also fixes a wrong link.

/// Opens the camera for ONE code and returns it (null if closed).
Future<String?> scanOneCode(BuildContext context, {String? title}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ScanOne(title: title)));

class _ScanOne extends StatefulWidget {
  const _ScanOne({this.title});
  final String? title;

  @override
  State<_ScanOne> createState() => _ScanOneState();
}

class _ScanOneState extends State<_ScanOne> {
  final _c = MobileScannerController(formats: const [
    BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE,
    BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.dataMatrix, BarcodeFormat.qrCode,
  ]);
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title ?? tr('Skani barcode')),
          actions: [IconButton(tooltip: tr('Tochi'), onPressed: () => _c.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined))],
        ),
        body: Stack(children: [
          MobileScanner(
            controller: _c,
            onDetect: (cap) {
              final code = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue?.trim();
              if (_done || code == null || code.isEmpty) return;
              _done = true;
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop(code);
            },
          ),
          Center(
            child: Container(
              width: 280,
              height: 170,
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3DDC97), width: 3), borderRadius: BorderRadius.circular(22)),
            ),
          ),
        ]),
      );
}

/// Links [code] to the product. When the code already belongs to ANOTHER
/// product, says which, and (if this person may) offers to move it here.
/// Returns true when the code is now on this product.
Future<bool> linkOrMoveBarcode(
  BuildContext context, {
  required ApiClient api,
  required String code,
  required int productId,
  required String productName,
  String? unitName,
}) async {
  void toast(String t, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: error ? const Color(0xFFC2412D) : null));
  }

  try {
    await api.post('products/$productId/barcodes', {'code': code, 'unit_name': ?unitName});
    toast(tr('Barcode imeunganishwa na :name.', {'name': productName}));
    return true;
  } on ApiException catch (e) {
    if (e.code != 'barcode_taken' || !context.mounted) {
      toast(e.message, error: true);
      return false;
    }
    final owner = '${(e.data['taken_by'] as Map?)?['name'] ?? ''}';
    if (e.data['can_move'] != true) {
      toast(e.message, error: true);
      return false;
    }
    final ok = await confirmDialog(
      context,
      title: tr('Barcode hii ni ya :a', {'a': owner}),
      message: tr('Kama imeunganishwa kimakosa, ihamishe kwenye :b. Haitajulikana tena kama :a.', {'a': owner, 'b': productName}),
      confirm: tr('Hamisha hapa'),
    );
    if (ok != true) return false;
    try {
      await api.post('barcodes/move', {'code': code, 'product_id': productId, 'unit_name': ?unitName});
      toast(tr('Barcode sasa ni ya :name.', {'name': productName}));
      return true;
    } on ApiException catch (e2) {
      toast(e2.message, error: true);
      return false;
    }
  }
}
