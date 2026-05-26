import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_state.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  static Future<Map<String, dynamic>> get(String path) =>
      _request('GET', path);

  static Future<Map<String, dynamic>> post(String path,
          [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body);

  static Future<Map<String, dynamic>> delete(String path,
          [Map<String, dynamic>? body]) =>
      _request('DELETE', path, body: body);

  static Future<Map<String, dynamic>> postPublic(
      String path, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return _parse(response);
    } on SocketException {
      throw const ApiException(0, 'No internet connection. Check your network and try again.');
    }
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    final token = AuthState.instance.accessToken;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}$path');
      final http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
        case 'DELETE':
          response = await http.delete(uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null);
        default:
          response = await http.post(uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null);
      }
      if (response.statusCode == 401 && !isRetry) {
        await _tryRefresh();
        return _request(method, path, body: body, isRetry: true);
      }
      return _parse(response);
    } on SocketException {
      throw const ApiException(0, 'No internet connection. Check your network and try again.');
    }
  }

  static Future<void> refreshTokens() => _tryRefresh();

  static Future<void> _tryRefresh() async {
    final refresh = AuthState.instance.refreshToken;
    if (refresh == null) {
      await AuthState.instance.clear();
      throw const ApiException(401, 'Session expired. Please sign in again.');
    }
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $refresh',
        },
      );
      if (response.statusCode != 200) {
        await AuthState.instance.clear();
        throw const ApiException(401, 'Session expired. Please sign in again.');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      await AuthState.instance.setTokens(
        json['access_token'] as String,
        json['refresh_token'] as String,
      );
    } on SocketException {
      throw const ApiException(0, 'No internet connection.');
    }
  }

  static Map<String, dynamic> _parse(http.Response response) {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
          response.statusCode, json['error'] as String? ?? 'Request failed');
    }
    return json;
  }
}
