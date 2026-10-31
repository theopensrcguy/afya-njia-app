/// App settings that change between your Mac, an emulator and the real phone.
///
/// They are read at BUILD time with --dart-define, so you never edit code to
/// point the app somewhere else:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
///
/// Default 127.0.0.1 works in the iOS Simulator, which shares your Mac's
/// network. A real iPhone is a different device, so it needs your Mac's
/// Wi-Fi IP address instead (see README).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api',
);

/// Which pharmacy this counter phone belongs to (from the seeder: 1).
const int pharmacyId = int.fromEnvironment('PHARMACY_ID', defaultValue: 1);
