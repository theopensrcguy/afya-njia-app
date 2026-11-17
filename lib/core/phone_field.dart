import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';

/// A country for phone numbers: its code and exactly how many digits follow it.
/// The same list as the server (App\Support\Phone) and the web (Afya.phone).
class PhoneCountry {
  const PhoneCountry(this.code, this.flag, this.name, this.digits, this.first);

  final String code;
  final String flag;
  final String name;
  final int digits;

  /// Allowed first digits of a mobile number.
  final String first;
}

const phoneCountries = [
  PhoneCountry('255', '🇹🇿', 'Tanzania', 9, '67'),
  PhoneCountry('254', '🇰🇪', 'Kenya', 9, '17'),
  PhoneCountry('256', '🇺🇬', 'Uganda', 9, '7'),
  PhoneCountry('250', '🇷🇼', 'Rwanda', 9, '7'),
  PhoneCountry('257', '🇧🇮', 'Burundi', 8, '67'),
  PhoneCountry('243', '🇨🇩', 'DR Congo', 9, '89'),
  PhoneCountry('260', '🇿🇲', 'Zambia', 9, '79'),
  PhoneCountry('265', '🇲🇼', 'Malawi', 9, '89'),
  PhoneCountry('258', '🇲🇿', 'Mozambique', 9, '8'),
];

/// "0712 345 678" / "+255 712…" / "255712345678" → (Tanzania, "712345678").
(PhoneCountry, String) parsePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  final c = phoneCountries.firstWhere((x) => d.startsWith(x.code) && d.length > x.code.length + 2, orElse: () => phoneCountries.first);
  if (d.startsWith(c.code)) d = d.substring(c.code.length);
  d = d.replaceFirst(RegExp(r'^0+'), '');
  return (c, d.length > c.digits ? d.substring(0, c.digits) : d);
}

/// Null when [full] ("255712345678") is empty or a complete mobile number; else what is wrong.
String? phoneProblem(String full) {
  if (full.isEmpty) return null;
  final (c, local) = parsePhone(full);
  if (local.length < c.digits) return tr('Namba ya :country iwe na tarakimu :n baada ya +:code.', {'country': c.name, 'n': c.digits, 'code': c.code});
  if (!c.first.contains(local[0])) return tr('Namba hii si ya simu ya mkononi ya :country.', {'country': c.name});
  return null;
}

/// A phone number: the country code picker, then only that country's digits
/// (no more than it allows, grouped 712 345 678). The leading 0 people type
/// is dropped by itself; a pasted +255… picks the country. [controller] holds
/// the whole number for the server ("255712345678", or "" when empty), so
/// screens read and send controller.text as before.
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.icon,
    this.focusNode,
    this.style,
    this.fillColor,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final IconData? icon;
  final FocusNode? focusNode;
  final TextStyle? style;
  final Color? fillColor;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late PhoneCountry _country;
  final _local = TextEditingController();
  String? _problem;

  @override
  void initState() {
    super.initState();
    _read();
    if (widget.controller.text != _full) widget.controller.text = _full;
    widget.controller.addListener(_outside);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_outside);
    _local.dispose();
    super.dispose();
  }

  String get _full {
    final d = _local.text.replaceAll(' ', '');
    return d.isEmpty ? '' : '${_country.code}$d';
  }

  void _read() {
    final (c, local) = parsePhone(widget.controller.text);
    _country = c;
    _local.text = _group(local);
  }

  /// The screen set the number itself (e.g. after loading): show it.
  void _outside() {
    if (widget.controller.text != _full) {
      setState(_read);
      if (widget.controller.text != _full) widget.controller.text = _full;   // one way: "255…"
    }
  }

  static String _group(String d) => d.replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]} ');

  void _changed() {
    final full = _full;
    if (widget.controller.text != full) widget.controller.text = full;
    setState(() => _problem = phoneProblem(full));
    widget.onChanged?.call(full);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint ?? _group('X' * _country.digits);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: DropdownButton<PhoneCountry>(
          value: _country,
          underline: const SizedBox.shrink(),
          style: widget.style?.copyWith(fontSize: (widget.style?.fontSize ?? 16) * 0.9),
          items: [
            for (final c in phoneCountries)
              DropdownMenuItem(value: c, child: Text('${c.flag} +${c.code}')),
          ],
          onChanged: (c) {
            if (c == null) return;
            setState(() {
              _country = c;
              final d = _local.text.replaceAll(' ', '');
              _local.text = _group(d.length > c.digits ? d.substring(0, c.digits) : d);
            });
            _changed();
          },
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _local,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.phone,
          textInputAction: widget.textInputAction,
          style: widget.style,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [_PhoneDigits(this)],
          onChanged: (_) => _changed(),
          onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(_full),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: hint,
            helperText: widget.helper,
            errorText: _problem,
            prefixIcon: widget.icon == null ? null : Icon(widget.icon),
            filled: widget.fillColor != null,
            fillColor: widget.fillColor,
          ),
        ),
      ),
    ]);
  }
}

/// Digits only, the leading 0 dropped, at most the country's digits, grouped
/// in threes. A pasted number with a country code switches the country.
class _PhoneDigits extends TextInputFormatter {
  _PhoneDigits(this.field);

  final _PhoneFieldState field;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    for (final c in phoneCountries) {
      if (d.length > c.digits && d.startsWith(c.code) && d.length - c.code.length <= c.digits + 1) {
        field._country = c;
        d = d.substring(c.code.length);
        break;
      }
    }
    d = d.replaceFirst(RegExp(r'^0+'), '');
    final max = field._country.digits;
    if (d.length > max) d = d.substring(0, max);
    final text = _PhoneFieldState._group(d);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
