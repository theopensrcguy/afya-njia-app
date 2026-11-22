import 'package:flutter/services.dart';

/// Shillings are whole numbers everywhere (same rule as the server), so money
/// is an int and formatting is just adding thousands separators.
///
///   formatTsh(12500)  -> "TSh 12,500"
///   formatTsh(-35000) -> "− TSh 35,000"
String formatTsh(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
  }
  return '${amount < 0 ? '− ' : ''}TSh $buffer';
}

/// "1250000" → "1,250,000" (no currency): what a money box shows.
String groupDigits(int n) => formatTsh(n).replaceFirst('TSh ', '').replaceFirst('− ', '-');

/// The number in a money box, commas or not: "1,250,000" → 1250000.
int? moneyValue(String text) => int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));

/// Every amount box in the app: digits only, grouped in thousands as you
/// type ("125,000"), with the cursor kept after the same digit.
class MoneyInput extends TextInputFormatter {
  const MoneyInput();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return const TextEditingValue();
    // Digits to the right of the cursor stay to the right of it.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final after = newValue.text.substring(cursor).replaceAll(RegExp(r'[^0-9]'), '').length;
    final grouped = groupDigits(int.parse(digits.length > 15 ? digits.substring(0, 15) : digits));
    var pos = grouped.length;
    for (var seen = 0; pos > 0 && seen < after; pos--) {
      if (grouped[pos - 1] != ',') seen++;
    }
    return TextEditingValue(text: grouped, selection: TextSelection.collapsed(offset: pos));
  }
}

// ---------------------------------------------------------------- costs (v0.49)
// Buying cost keeps ONE decimal place (a box of 30 at 2,000 = 66.7 a tablet).
// Selling prices and every total stay whole shillings.

/// A cost from the server (int or 66.7) as a number.
num asCost(dynamic v) => v is num ? v : num.tryParse('$v'.replaceAll(',', '')) ?? 0;

/// "1,250.5" or "2,000": the decimal only when there is one.
String costText(num v) {
  final r = (v * 10).round() / 10;
  if (r == r.roundToDouble()) return groupDigits(r.round());
  final whole = r.truncate();
  final tenth = ((r - whole).abs() * 10).round();
  return '${whole == 0 && r < 0 ? '-0' : groupDigits(whole)}.$tenth';
}

/// "TSh 1,250.5".
String formatCost(num v) => '${v < 0 ? '− ' : ''}TSh ${costText(v.abs())}';

/// The number in a cost box: "1,250.5" → 1250.5 (null when empty).
num? costValue(String text) {
  final t = text.replaceAll(RegExp(r'[^0-9.]'), '');
  if (t.isEmpty || t == '.') return null;
  final v = num.tryParse(t);
  if (v == null) return null;
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.round() : r;
}

/// A buying-price box: thousands commas, and at most one digit after a point.
class CostInput extends TextInputFormatter {
  const CostInput();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    final m = RegExp(r'^(\d*)(\.\d?)?').firstMatch(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    var whole = (m?.group(1) ?? '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final dec = m?.group(2) ?? '';
    if (whole.isEmpty && dec.isEmpty) return const TextEditingValue();
    if (whole.length > 12) whole = whole.substring(0, 12);
    final text = '${whole.isEmpty ? '0' : groupDigits(int.parse(whole))}$dec';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
