// Small helpers for showing server data, shared by every screen.

const paymentLabels = {'cash': 'Taslimu', 'mobile': 'Simu', 'insurance': 'Bima'};

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

/// "Dakika 6 zilizopita", "Saa 2 zilizopita": how long ago, in Swahili.
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'sasa hivi';
  if (diff.inMinutes < 60) return 'dakika ${diff.inMinutes} zilizopita';
  if (diff.inHours < 24) return 'saa ${diff.inHours} zilizopita';
  return 'siku ${diff.inDays} zilizopita';
}

/// GET shifts/current means "no open shift" with null, but Laravel turns
/// response()->json(null) into an empty object {}. Treat both as "none".
Map<String, dynamic>? openShiftOrNull(dynamic data) =>
    data is Map<String, dynamic> && data.isNotEmpty ? data : null;

const _weekdays = ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];
const _months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];

/// Short Swahili day names for chart labels, Monday first: J3 J4 J5 Al Ij J1 J2.
const weekdayShort = ['J3', 'J4', 'J5', 'Al', 'Ij', 'J1', 'J2'];

/// "Jumamosi, 31 Okt". DateTime.weekday is 1 (Monday) to 7 (Sunday).
String swahiliDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "Oktoba"-style month title for the chart.
const monthNames = [
  'Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni',
  'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba',
];

/// Habari za asubuhi / mchana / jioni, by the phone's clock.
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Habari za asubuhi';
  if (h < 16) return 'Habari za mchana';
  return 'Habari za jioni';
}

/// A sale's lines as one short line: "Paracetamol 500mg ×2, ORS ×1".
String itemsSummary(List items) =>
    items.map((i) => '${i['name']} ×${asInt(i['quantity'])}').join(', ');
