import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'i18n.dart';

/// Product photos (v0.46.1): take one with the camera or pick one, and it is
/// on the product everywhere (stock list, shelves, stock-take, and later an
/// online shop). Offered while counting stock, so one walk along the shelf
/// does both jobs.
///
/// Returns the new photo link, '' when the photo was removed, or null when
/// nothing changed.
Future<String?> editProductPhoto(BuildContext context, {required ApiClient api, required int productId, String? current}) async {
  final has = current != null && current.isNotEmpty;
  // v0.48.5: scroll-controlled with a smaller preview, so "Ondoa" is never
  // pushed below the screen (a 9/16 sheet hid it on most iPhones).
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(has ? 'Picha ya bidhaa' : 'Weka picha ya bidhaa'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const T('Boksi mbele, mwanga mzuri, jina lisomeke', style: TextStyle(fontSize: 12.5, color: Color(0xFF5B6F69))),
          const SizedBox(height: 14),
          if (has)
            GestureDetector(
              onTap: () => _zoom(sheet, current),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 170,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(current, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: const Color(0xFFEFF4F2))),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(99)),
                        child: const Icon(Icons.zoom_out_map_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          if (has) const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _action(sheet, Icons.photo_camera_outlined, tr(has ? 'Piga mpya' : 'Piga picha'), 'camera')),
            const SizedBox(width: 10),
            Expanded(child: _action(sheet, Icons.photo_library_outlined, tr('Chagua picha'), 'gallery')),
            if (has) ...[
              const SizedBox(width: 10),
              Expanded(child: _action(sheet, Icons.delete_outline_rounded, tr('Ondoa'), 'remove', danger: true)),
            ],
          ]),
        ]),
      ),
    ),
  );
  if (choice == 'remove' && context.mounted) {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const T('Ondoa picha?'),
        content: const T('Bidhaa itaonyesha alama ya kifungashio badala ya picha. Unaweza kuweka nyingine wakati wowote.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const T('Hapana')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC2412D)),
            onPressed: () => Navigator.of(d).pop(true),
            child: const T('Ondoa'),
          ),
        ],
      ),
    );
    if (sure != true) return null;
  }
  if (choice == null || !context.mounted) return null;
  try {
    if (choice == 'remove') {
      await api.delete('products/$productId/photo');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Picha imeondolewa.'))));
      return '';
    }
    // Small enough to send on a slow line, big enough for a shop page later.
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 82,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
    final r = await api.upload('products/$productId/photo', 'photo', bytes, name) as Map<String, dynamic>;
    return '${r['photo_url'] ?? ''}';
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    // Camera refused (no permission) or the phone said no.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Kamera haikufunguka. Ruhusu Afya Njia kutumia kamera kwenye Settings.'))));
    }
  }
  return null;
}

Widget _action(BuildContext sheet, IconData icon, String label, String value, {bool danger = false}) {
  final fg = danger ? const Color(0xFFC2412D) : const Color(0xFF0E3B31);
  return Material(
    color: danger ? const Color(0xFFFBE9E5) : const Color(0xFFEFF4F2),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(sheet).pop(value),
      child: SizedBox(
        height: 84,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: fg, size: 26),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    ),
  );
}

/// The photo full screen, pinch to zoom.
void _zoom(BuildContext context, String url) => Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url))),
      ),
    ));

/// The product's photo in a rounded square, or [fallback] (the pack icon)
/// when there is none or it can't load. [onTap] opens the photo editor.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.url, required this.fallback, this.size = 44, this.radius = 12, this.onTap, this.badge = false});

  final String? url;
  final Widget fallback;
  final double size;
  final double radius;
  final VoidCallback? onTap;

  /// A small camera mark: "tap to add a photo".
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: has
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) => progress == null ? child : Container(color: const Color(0xFFEFF4F2)),
              )
            : fallback,
      ),
    );
    final withBadge = badge && !has
        ? Stack(clipBehavior: Clip.none, children: [
            box,
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xFF0E3B31), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.photo_camera_rounded, size: 11, color: Colors.white),
              ),
            ),
          ])
        : box;
    return onTap == null ? withBadge : GestureDetector(onTap: onTap, child: withBadge);
  }
}
