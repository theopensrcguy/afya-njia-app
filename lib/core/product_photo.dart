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
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (current != null && current.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(aspectRatio: 4 / 3, child: Image.network(current, fit: BoxFit.cover)),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: T(current == null || current.isEmpty ? 'Piga picha' : 'Piga picha mpya'),
            subtitle: const T('Boksi mbele, mwanga mzuri, jina lisomeke'),
            onTap: () => Navigator.of(sheet).pop('camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const T('Chagua kwenye picha za simu'),
            onTap: () => Navigator.of(sheet).pop('gallery'),
          ),
          if (current != null && current.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFA8321F)),
              title: const T('Ondoa picha', style: TextStyle(color: Color(0xFFA8321F))),
              onTap: () => Navigator.of(sheet).pop('remove'),
            ),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  try {
    if (choice == 'remove') {
      await api.delete('products/$productId/photo');
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
