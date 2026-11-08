import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/staff.dart';
import 'api_client.dart';
import 'i18n.dart';
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

  /// What the sign-in screen may show on THIS device. The server only tells
  /// an approved device any names:
  ///   personal → [SignInInfo.lastUser]: "Karibu tena, Hamisi" + PIN
  ///   shared   → [SignInInfo.staff]: the counter phone, most recent first
  ///   new      → nothing: phone number + PIN
  Future<SignInInfo> loadSignIn() async {
    final d = await api.post('login/device', {'device_uid': await deviceUid()}) as Map<String, dynamic>;
    return SignInInfo(
      mode: '${d['mode']}',
      lastUser: d['last_user'] == null ? null : Staff.fromJson(d['last_user'] as Map<String, dynamic>),
      staff: [for (final s in ((d['staff'] as List?) ?? const [])) Staff.fromJson(s as Map<String, dynamic>)],
    );
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
  ///
  /// Either [staff] (picked on an approved device) or [phone] (typed on a new one).
  Future<void> login(Staff? staff, String pin, {String? phone}) async {
    final who = staff?.name ?? 'mpya';
    final data = await api.post('login/pin', {
      if (staff != null) 'user_id': staff.id else 'phone': phone,
      'pin': pin,
      'device_uid': await deviceUid(),
      // A browser is a device too: the owner approves it like a phone.
      'device_name': kIsWeb ? 'Kivinjari ($who)' : 'Simu ($who)',
    }) as Map<String, dynamic>;

    api.token = data['token'] as String;
    user = Staff.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: api.token);
    await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
    await _syncLanguage();
    notifyListeners();
  }

  /// Just signed in. Picked a language on the sign-in screen? That becomes this
  /// person's choice (saved on the server, so the web follows). Otherwise the
  /// app switches to the language they chose before, on any phone or the web.
  Future<void> _syncLanguage() async {
    if (lang.takeSignedOutChoice()) {
      await setLanguage(lang.code);
    } else {
      await lang.apply(user?.locale);
    }
  }

  /// The language switch while signed in: this phone now, and the person's
  /// account (web and other phones) too. Offline: the phone still switches.
  Future<void> setLanguage(String code) async {
    await lang.apply(code);
    try {
      await api.patch('me/locale', {'locale': code});
    } on ApiException {
      // offline: it's saved next time they switch
    }
  }

  /// Re-read who I am and what I may do now (the owner may have granted or
  /// revoked something, or a "until Saturday" grant may have ended).
  /// Quiet on failure: the old list stays and the server still enforces.
  Future<void> refreshMe() async {
    if (!isLoggedIn) return;
    try {
      final fresh = Staff.fromJson(await api.get('me') as Map<String, dynamic>);
      final changed = fresh.permissions.join(',') != user?.permissions.join(',') || fresh.mustChangePin != user?.mustChangePin;
      user = fresh;
      await _storage.write(key: _userKey, value: jsonEncode(fresh.toJson()));
      // Switched language on the web (or another phone)? Follow it here.
      await lang.apply(fresh.locale);
      if (changed) notifyListeners(); // screens redraw with the new buttons
    } on ApiException {
      // offline or similar: keep what we had
    }
  }

  /// Change my own PIN. Throws ApiException ('bad_pin' = current PIN wrong;
  /// 422 with a message for an easy or unchanged new PIN).
  Future<void> changeOwnPin(String current, String fresh) async {
    final data = await api.post('me/pin', {'current_pin': current, 'new_pin': fresh}) as Map<String, dynamic>;
    user = Staff.fromJson(data);
    await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
    notifyListeners(); // a forced change is done: the gate now shows the home screen
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

/// What the sign-in screen shows on this device (see [Session.loadSignIn]).
class SignInInfo {
  const SignInInfo({required this.mode, this.lastUser, this.staff = const []});

  final String mode; // personal | shared | new
  final Staff? lastUser;
  final List<Staff> staff;
}
