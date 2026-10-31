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
