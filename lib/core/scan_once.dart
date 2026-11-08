import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'brand.dart';
import 'i18n.dart';

/// Open the camera, read ONE barcode, come back with it (null if closed).
/// Used while receiving: scanning the box teaches the shop its barcode.
Future<String?> scanOnce(BuildContext context, {String? title}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ScanOnce(title: title ?? tr('Skani barcode ya boksi'))));
}

class _ScanOnce extends StatefulWidget {
  const _ScanOnce({required this.title});

  final String title;

  @override
  State<_ScanOnce> createState() => _ScanOnceState();
}

class _ScanOnceState extends State<_ScanOnce> {
  final _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title)),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue?.trim();
            if (_done || code == null || code.isEmpty) return;
            _done = true;
            Navigator.of(context).pop(code);
          },
        ),
        Center(
          child: Container(
            width: 280,
            height: 170,
            decoration: BoxDecoration(border: Border.all(color: mintAccent, width: 3), borderRadius: BorderRadius.circular(22)),
          ),
        ),
      ]),
    );
  }
}
