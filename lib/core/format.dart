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
