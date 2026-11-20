/// Where the app finds the server. Read at BUILD time.
///
/// The default is the live server, so a plain `flutter run` (and every build
/// for the pilot phones / TestFlight) talks to the real shop data:
///
///   flutter run
///
/// To test against the Laravel on your Mac instead, say so when building:
///
///   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api      (iOS Simulator)
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api   (iPhone, your Mac's Wi-Fi IP)
///
/// It must be the domain (nginx picks the site by name; the bare IP gives 404)
/// and https (iOS refuses plain http to internet servers).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://afyanjia.saola.co.tz/api',
);

/// Which pharmacy this counter phone belongs to (from the seeder: 1).
const int pharmacyId = int.fromEnvironment('PHARMACY_ID', defaultValue: 1);
