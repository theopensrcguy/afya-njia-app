import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'brand.dart';
import 'i18n_en.dart';

/// Kiswahili / English.
///
/// The app is written in Kiswahili, and that text is also the key: tr('Hifadhi')
/// gives "Save" in English (from i18n_en.dart) and 'Hifadhi' in Kiswahili. A
/// text missing from the English list simply stays in Kiswahili, so a forgotten
/// one never breaks a screen. Placeholders work like on the server:
/// tr('Bidhaa :n', {'n': 3}).
///
/// The choice belongs to the person (saved on their account, the same on the
/// web). Before anyone signs in, this phone remembers what was last used.
class Lang extends ChangeNotifier {
  Lang._();
  static final instance = Lang._();

  static const supported = {'sw': 'Kiswahili', 'en': 'English'};
  static const _storage = FlutterSecureStorage();
  static const _key = 'afya_lugha';

  String code = 'sw';
  bool get isEnglish => code == 'en';

  /// Chosen on the sign-in screen: becomes the person's choice once they sign in.
  bool _chosenSignedOut = false;

  static String? valid(String? c) => supported.containsKey(c) ? c : null;

  /// On app start, before the first screen.
  Future<void> load() async {
    try {
      code = valid(await _storage.read(key: _key)) ?? 'sw';
    } catch (_) {
      code = 'sw';
    }
    notifyListeners();
  }

  /// Show the app in [c] (from the server, or a tap on the switch).
  Future<void> apply(String? c) async {
    final v = valid(c);
    if (v == null || v == code) return;
    code = v;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: v);
    } catch (_) {}
  }

  /// The switch on the sign-in screen: remembered, and saved on the person at sign-in.
  Future<void> chooseSignedOut(String c) async {
    _chosenSignedOut = true;
    await apply(c);
  }

  /// Read once at sign-in: did they pick a language just before?
  bool takeSignedOutChoice() {
    final chosen = _chosenSignedOut;
    _chosenSignedOut = false;
    return chosen;
  }
}

final lang = Lang.instance;

final _placeholder = RegExp(r':([a-z_]+)');

/// Kiswahili → the chosen language. See [Lang].
String tr(String sw, [Map<String, Object?> args = const {}]) {
  final text = lang.isEnglish ? (en[sw] ?? sw) : sw;
  if (args.isEmpty) return text;
  return text.replaceAllMapped(_placeholder, (m) => args.containsKey(m[1]) ? '${args[m[1]]}' : m[0]!);
}

/// Text('Hifadhi') that follows the language: T('Hifadhi'). Can stay const.
class T extends StatelessWidget {
  const T(this.data, {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) =>
      Text(tr(data), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap);
}

/// "Kiswahili | English", for the sign-in screen (on green) and the More menu.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key, required this.onChanged, this.onDark = false});

  final ValueChanged<String> onChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in Lang.supported.entries)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(e.value),
              selected: lang.code == e.key,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: onDark ? Colors.white54 : Colors.black12),
              backgroundColor: onDark ? Colors.transparent : null,
              selectedColor: onDark ? Colors.white : brandGreen,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: lang.code == e.key ? (onDark ? brandGreen : Colors.white) : (onDark ? Colors.white : inkColor),
              ),
              onSelected: (_) => onChanged(e.key),
            ),
          ),
      ],
    );
  }
}
