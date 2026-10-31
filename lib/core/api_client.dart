import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

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

  Map<String, String> _headers() => {
        // Without this, Laravel answers errors with an HTML page instead of JSON.
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 15));
    } on SocketException {
      throw ApiException('Hakuna mtandao. Angalia Wi-Fi au data.', code: 'offline');
    } on TimeoutException {
      throw ApiException('Seva haijajibu. Jaribu tena.', code: 'timeout');
    } on http.ClientException {
      throw ApiException('Imeshindwa kufikia seva.', code: 'offline');
    }

    final dynamic data = res.body.isEmpty ? null : _tryDecode(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException('Muda wa kuingia umeisha. Ingia tena.', code: 'session_expired', status: 401);
    }
    if (res.statusCode == 429) {
      throw ApiException('Majaribio mengi. Subiri dakika moja.', code: 'too_many_attempts', status: 429);
    }

    final message = (data is Map && data['message'] is String)
        ? data['message'] as String
        : 'Hitilafu ya seva (${res.statusCode}).';
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
