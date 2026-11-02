import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/staff.dart';
import 'api_client.dart';
import 'ids.dart';

/// Who is signed in on this phone, and the token that proves it.
///
/// It is a ChangeNotifier: when someone logs in or out it calls
/// notifyListeners(), and any widget listening (main.dart) rebuilds and shows
/// the right screen. That is the whole idea of state management in Flutter:
/// data changes in one place, the screens that depend on it redraw themselves.
class Session extends ChangeNotifier {
  Session(this.api) {
    // If the server rejects the token at any point, quietly sign out.
    api.onUnauthorized = () => _clear();
  }

  final ApiClient api;

  // Secure storage = the iPhone Keychain (Android Keystore on Android).
  // The token is a key to the shop's data, so it does not go in plain
  // SharedPreferences, which any backup or jailbreak could read.
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _deviceKey = 'device_uid';

  Staff? user;
  bool restored = false;

  bool get isLoggedIn => user != null && api.token != null;

  /// On app start: was someone already signed in before the app closed?
  Future<void> restore() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token != null && userJson != null) {
      api.token = token;
      user = Staff.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    }
    restored = true;
    notifyListeners();
  }

  /// People shown on the PIN screen.
  Future<List<Staff>> loadStaff() async {
    final data = await api.get('pharmacies/$pharmacyId/staff') as List<dynamic>;
    return data.map((e) => Staff.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// This phone's permanent id, created the first time the app runs.
  ///
  /// It's random (not the phone's serial number), so it identifies the
  /// installation without revealing anything about the person. The owner
  /// approves this id once; after that, the PIN works on this phone.
  /// Deleting and reinstalling the app makes a new id that needs approval again.
  Future<String> deviceUid() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null) return existing;

    final id = randomId();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  /// Throws ApiException:
  ///   'bad_pin'        – wrong PIN
  ///   'device_pending' – right PIN, but the owner hasn't approved this phone yet
  ///                      (e.data['pairing_code'] is the number to show him)
  ///   'device_revoked' – the owner removed this phone
  Future<void> login(Staff staff, String pin) async {
    final data = await api.post('login/pin', {
      'user_id': staff.id,
      'pin': pin,
      'device_uid': await deviceUid(),
      'device_name': 'Simu ya ${staff.name}',
    }) as Map<String, dynamic>;

    api.token = data['token'] as String;
    user = Staff.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: api.token);
    await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
    notifyListeners();
  }

  /// Re-read who I am and what I may do now (the owner may have granted or
  /// revoked something, or a "until Saturday" grant may have ended).
  /// Quiet on failure: the old list stays and the server still enforces.
  Future<void> refreshMe() async {
    if (!isLoggedIn) return;
    try {
      final fresh = Staff.fromJson(await api.get('me') as Map<String, dynamic>);
      final changed = fresh.permissions.join(',') != user?.permissions.join(',');
      user = fresh;
      await _storage.write(key: _userKey, value: jsonEncode(fresh.toJson()));
      if (changed) notifyListeners(); // screens redraw with the new buttons
    } on ApiException {
      // offline or similar: keep what we had
    }
  }

  Future<void> logout() async {
    try {
      await api.post('logout');
    } on ApiException {
      // Already invalid or offline: signing out locally is still correct.
    }
    await _clear();
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    notifyListeners();
  }
}
