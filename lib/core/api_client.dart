import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'i18n.dart';

/// Every failure the screens need to show, in one shape.
///
/// [message] is ready to show the user (the server already writes shop-rule
/// errors in Swahili). [code] lets code react to a specific case, for example
/// 'insufficient_stock' or 'session_expired'.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'error', this.status, this.data = const {}});

  final String message;
  final String code;
  final int? status;

  /// The full error body, for errors that carry extra fields
  /// (e.g. 'device_pending' carries the 'pairing_code' to show).
  final Map<String, dynamic> data;

  @override
  String toString() => 'ApiException($status, $code): $message';
}

/// The only place in the app that talks HTTP.
///
/// Why one class: headers, the token, timeouts and error handling are written
/// once. Screens just call get()/post() and either get data or an ApiException.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Set after login; sent on every request as "Authorization: Bearer ...".
  String? token;

  /// Called when the server says the token is no longer valid (401),
  /// so the app can send the user back to the PIN screen.
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    final uri = Uri.parse('$apiBaseUrl/$path').replace(queryParameters: query);
    return _send(() => _http.get(uri, headers: _headers()));
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) {
    final uri = Uri.parse('$apiBaseUrl/$path');
    return _send(() => _http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})));
  }

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) {
    final uri = Uri.parse('$apiBaseUrl/$path');
    return _send(() => _http.patch(uri, headers: _headers(), body: jsonEncode(body ?? {})));
  }

  Future<dynamic> delete(String path) {
    final uri = Uri.parse('$apiBaseUrl/$path');
    return _send(() => _http.delete(uri, headers: _headers()));
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) {
    final uri = Uri.parse('$apiBaseUrl/$path');
    return _send(() => _http.put(uri, headers: _headers(), body: jsonEncode(body ?? {})));
  }

  Map<String, String> _headers() => {
        // Without this, Laravel answers errors with an HTML page instead of JSON.
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        // Kiswahili / English for the server's messages. After sign-in the
        // server uses the person's own saved choice instead.
        'X-Lang': lang.code,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Send one file as a form upload (the invoice photo). A longer timeout:
  /// a photo on a slow connection takes much more than 15 seconds.
  ///
  /// Bytes, not a file path: a browser has no file system path (web build).
  Future<dynamic> upload(String path, String field, Uint8List bytes, String filename) {
    final uri = Uri.parse('$apiBaseUrl/$path');
    return _send(() async {
      final req = http.MultipartRequest('POST', uri)
        // No JSON Content-Type here: MultipartRequest sets its own.
        ..headers.addAll({'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'})
        ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
      return http.Response.fromStream(await _http.send(req));
    }, timeout: const Duration(seconds: 60));
  }

  /// Raw bytes, for files the server keeps private (the invoice photo): they
  /// need the token, so Image.network can't fetch them by itself.
  Future<Uint8List> getBytes(String path) async {
    final uri = Uri.parse('$apiBaseUrl/$path');
    final res = await _sendRaw(() => _http.get(uri, headers: {if (token != null) 'Authorization': 'Bearer $token'}),
        const Duration(seconds: 30));
    if (res.statusCode == 200) return res.bodyBytes;
    if (res.statusCode == 401) onUnauthorized?.call();
    throw ApiException(tr('Imeshindwa kupakua faili (:status_code).', {'status_code': res.statusCode}), status: res.statusCode);
  }

  /// The network part shared by _send and getBytes: no internet, timeout.
  Future<http.Response> _sendRaw(Future<http.Response> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException(tr('Seva haijajibu. Jaribu tena.'), code: 'timeout');
    } on http.ClientException {
      // No internet, server down, or (in a browser) the server refusing this
      // website (CORS). One message: the person can't fix the difference.
      throw ApiException(tr('Hakuna mtandao au seva haipatikani. Angalia Wi-Fi au data.'), code: 'offline');
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() request, {Duration timeout = const Duration(seconds: 15)}) async {
    final res = await _sendRaw(request, timeout);

    final dynamic data = res.body.isEmpty ? null : _tryDecode(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(tr('Muda wa kuingia umeisha. Ingia tena.'), code: 'session_expired', status: 401);
    }
    if (res.statusCode == 429) {
      throw ApiException(tr('Majaribio mengi. Subiri dakika moja.'), code: 'too_many_attempts', status: 429);
    }

    final message = (data is Map && data['message'] is String)
        ? data['message'] as String
        : tr('Hitilafu ya seva (:status_code).', {'status_code': res.statusCode});
    final code = (data is Map && data['code'] is String) ? data['code'] as String : 'error';
    throw ApiException(
      message,
      code: code,
      status: res.statusCode,
      data: data is Map<String, dynamic> ? data : const {},
    );
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
