import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  // Singleton pattern for easy access
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final String _baseUrl = 'http://13.125.127.75:8000';
  final _secureStorage = const FlutterSecureStorage();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Authentication token not found. Please log in.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(String path) async {
    final headers = await _getHeaders();
    final url = Uri.parse('$_baseUrl$path');
    return http.get(url, headers: headers);
  }

  Future<http.Response> post(String path, {dynamic body}) async {
    final headers = await _getHeaders();
    final url = Uri.parse('$_baseUrl$path');
    return http.post(url, headers: headers, body: json.encode(body));
  }

  Future<http.Response> put(String path, {dynamic body}) async {
    final headers = await _getHeaders();
    final url = Uri.parse('$_baseUrl$path');
    return http.put(url, headers: headers, body: json.encode(body));
  }

  Future<http.Response> delete(String path) async {
    final headers = await _getHeaders();
    final url = Uri.parse('$_baseUrl$path');
    return http.delete(url, headers: headers);
  }
}
