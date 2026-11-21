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
