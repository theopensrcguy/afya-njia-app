import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand.dart';
import 'i18n.dart';
import 'smooth.dart';

/// Maandishi (v0.50): how big the text is and which font, chosen on this phone.
///
/// Why the app needs its own setting: until now it followed the phone's text
/// size (Settings → Display → Text Size). A phone set large for messages made
/// every screen shout, and the counter's long medicine names stacked into
/// five lines. The default is now the app's own normal size; "Fuata simu"
/// brings back the phone's setting for anyone who needs big text.
class Appearance extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _kSize = 'afya.text.size';
  static const _kFont = 'afya.text.font';

  /// ndogo · kawaida · kubwa · simu (follow the phone)
  String size = 'kawaida';

  /// mfumo (the phone's own font) · laini (Nunito) · wazi (Inter)
  String font = 'mfumo';

  static const sizes = {'ndogo': 0.9, 'kawaida': 1.0, 'kubwa': 1.12};
  static const fonts = ['mfumo', 'laini', 'wazi'];

  Future<void> load() async {
    try {
      final s = await _storage.read(key: _kSize);
      final f = await _storage.read(key: _kFont);
      if (s != null && (sizes.containsKey(s) || s == 'simu')) size = s;
      if (f != null && fonts.contains(f)) font = f;
    } catch (_) {/* storage unavailable: defaults */}
  }

  Future<void> setSize(String v) async {
    if (v == size) return;
    size = v;
    notifyListeners();
    try { await _storage.write(key: _kSize, value: v); } catch (_) {}
  }

  Future<void> setFont(String v) async {
    if (v == font) return;
    font = v;
    notifyListeners();
    try { await _storage.write(key: _kFont, value: v); } catch (_) {}
  }

  /// The text scale for every screen. "simu" keeps the phone's own, but never
  /// past 1.3, beyond which rows and buttons can't hold their words.
  TextScaler scaler(TextScaler phone) {
    if (size == 'simu') return phone.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3);
    return TextScaler.linear(sizes[size] ?? 1.0);
  }

  /// null = the phone's own font (San Francisco on iPhone, Roboto on Android).
  /// The others come from google_fonts: downloaded once, then kept on the phone;
  /// with no internet the first time, the phone's font is used until it arrives.
  String? get fontFamily => switch (font) {
        'laini' => GoogleFonts.nunito().fontFamily,
        'wazi' => GoogleFonts.inter().fontFamily,
        _ => null,
      };

  static String sizeLabel(String k) => switch (k) {
        'ndogo' => tr('Ndogo'),
        'kubwa' => tr('Kubwa'),
        'simu' => tr('Fuata simu'),
        _ => tr('Kawaida'),
      };

  static String fontLabel(String k) => switch (k) {
        'laini' => tr('Laini'),
        'wazi' => tr('Wazi'),
        _ => tr('Ya simu'),
      };
}

final appearance = Appearance();

/// The sheet: size and font, with a preview of a counter row that changes as you choose.
Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => ListenableBuilder(
      listenable: appearance,
      builder: (sheet, _) {
        final fam = appearance.fontFamily;
        final scale = appearance.scaler(MediaQuery.of(context).textScaler);
        Widget option(String label, bool on, VoidCallback tap, {Widget? top}) => Expanded(
              child: Pressable(
                onTap: () {
                  tick();
                  tap();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: on ? primarySoft : pageBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? brandGreen : Colors.transparent, width: 1.5),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ?top,
                    if (top != null) const SizedBox(height: 4),
                    Text(label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? primaryStrong : inkColor)),
                  ]),
                ),
              ),
            );
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFD5DEDA), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              const T('Maandishi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: inkColor)),
              const SizedBox(height: 4),
              const T('Ukubwa na mtindo wa herufi kwenye simu hii.', style: TextStyle(fontSize: 13, color: mutedText)),
              const SizedBox(height: 16),
              // Preview: a counter row, drawn at the chosen size and font.
              MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scale),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: pageBackground, borderRadius: BorderRadius.circular(16)),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontFamily: fam),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.medication_outlined, color: brandGreen),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Paracetamol 500mg Tablet', maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: fam, fontWeight: FontWeight.w600, fontSize: 15, color: inkColor)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Expanded(child: Text(tr('Hisa: vidonge 120'), style: TextStyle(fontFamily: fam, fontSize: 12.5, color: mutedText))),
                            Text('TSh 200 / kidonge', style: TextStyle(fontFamily: fam, fontSize: 14, fontWeight: FontWeight.w700, color: brandGreen)),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const T('UKUBWA', style: TextStyle(fontSize: 11.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: mutedText)),
              const SizedBox(height: 8),
              Row(children: [
                for (final k in const ['ndogo', 'kawaida', 'kubwa', 'simu']) ...[
                  option(Appearance.sizeLabel(k), appearance.size == k, () => appearance.setSize(k),
                      top: k == 'simu'
                          ? const Icon(Icons.phone_iphone_rounded, size: 20, color: inkColor)
                          : Text('A', style: TextStyle(fontSize: 14 * (Appearance.sizes[k] ?? 1) * 1.3, fontWeight: FontWeight.w700, color: inkColor, height: 1.1))),
                  if (k != 'simu') const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 18),
              const T('MTINDO', style: TextStyle(fontSize: 11.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: mutedText)),
              const SizedBox(height: 8),
              Row(children: [
                for (final k in Appearance.fonts) ...[
                  option(Appearance.fontLabel(k), appearance.font == k, () => appearance.setFont(k),
                      top: Text('Aa',
                          style: TextStyle(
                              fontFamily: switch (k) { 'laini' => GoogleFonts.nunito().fontFamily, 'wazi' => GoogleFonts.inter().fontFamily, _ => null },
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                              height: 1.1))),
                  if (k != Appearance.fonts.last) const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 10),
              const T('"Fuata simu" inatumia ukubwa uliowekwa kwenye Settings za simu (hadi kiasi fulani, ili maandishi yasikatike).',
                  style: TextStyle(fontSize: 12, color: mutedText)),
            ]),
          ),
        );
      },
    ),
  );
}
