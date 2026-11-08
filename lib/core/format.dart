// Small helpers for showing server data, shared by every screen.

import 'i18n.dart';
import 'units.dart';

/// How each payment method is called, in the chosen language.
Map<String, String> get paymentLabels =>
    {'cash': tr('Taslimu'), 'mobile': lang.isEnglish ? 'Mobile money' : 'Simu', 'insurance': tr('Bima')};

String _two(int n) => n.toString().padLeft(2, '0');

/// "14:05", in the phone's local time. The server sends dates with their
/// timezone, so .toLocal() turns them into Tanzanian time on the phone.
String formatTime(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

DateTime? parseDate(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// Numbers from JSON may arrive as int, double or (rarely) text. Never crash on that.
int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// {"cash": 500, "mobile": 300}. Careful: when there are no sales, Laravel
/// sends an empty LIST [] instead of an empty object {}, so both are accepted.
Map<String, int> moneyMap(dynamic v) {
  if (v is Map) {
    return v.map((k, x) => MapEntry('$k', asInt(x)));
  }
  return {};
}

/// "dakika 6 zilizopita" / "6 minutes ago": how long ago.
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return tr('sasa hivi');
  if (diff.inMinutes < 60) return tr('dakika :n zilizopita', {'n': diff.inMinutes});
  if (diff.inHours < 24) return tr('saa :n zilizopita', {'n': diff.inHours});
  return tr('siku :n zilizopita', {'n': diff.inDays});
}

/// GET shifts/current means "no open shift" with null, but Laravel turns
/// response()->json(null) into an empty object {}. Treat both as "none".
Map<String, dynamic>? openShiftOrNull(dynamic data) =>
    data is Map<String, dynamic> && data.isNotEmpty ? data : null;

const _weekdays = ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];
const _months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];

const _weekdayShort = ['J3', 'J4', 'J5', 'Al', 'Ij', 'J1', 'J2'];

/// Short day names for chart labels, Monday first: J3 J4 J5 Al Ij J1 J2 / Mon … Sun.
List<String> get weekdayShort => [for (final d in _weekdayShort) tr(d)];

/// "Jumamosi, 31 Okt" / "Saturday, 31 Oct". DateTime.weekday is 1 (Monday) to 7 (Sunday).
String swahiliDate(DateTime d) => '${tr(_weekdays[d.weekday - 1])}, ${d.day} ${tr(_months[d.month - 1])}';

/// "Oktoba" / "October": month title for the chart.
List<String> get monthNames => [for (final m in _monthNames) tr(m)];

const _monthNames = [
  'Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni',
  'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba',
];

/// Habari za asubuhi / mchana / jioni, by the phone's clock.
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return tr('Habari za asubuhi');
  if (h < 16) return tr('Habari za mchana');
  return tr('Habari za jioni');
}

/// A sale's lines as one short line: "Paracetamol 500mg ×2 kadi, ORS ×1".
/// Items are {name, quantity, unit?}; the unit is left out when it's the base
/// unit's default "tablet"-type name, to keep the line short.
String itemsSummary(List items) => items.map((i) {
      final q = asInt(i['quantity']);
      final unit = '${i['unit'] ?? ''}'.toLowerCase();
      final plain = unit.isEmpty || const {'tablet', 'capsule', 'kidonge'}.contains(unit);
      return '${i['name']} ×$q${plain ? '' : ' ${unitLabel(unit, q)}'}';
    }).join(', ');
