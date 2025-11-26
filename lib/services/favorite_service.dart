import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:midas_project/models/favorite_model.dart';

class FavoriteService {
  static const String _baseUrl = 'http://13.125.127.75:8000';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 헤더에 토큰 추가
  Future<Map<String, String>> _getHeaders() async {
    final token = await _secureStorage.read(key: 'access_token');
    return {
      'accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 즐겨찾기 목록 조회
  Future<List<Favorite>> getFavorites({int skip = 0, int limit = 100}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/favorites/?skip=$skip&limit=$limit');

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Favorite.fromJson(json)).toList();
    } else {
      throw Exception('즐겨찾기 목록 조회 실패: ${response.statusCode} ${response.body}');
    }
  }

  /// 즐겨찾기 추가 (장소)
  Future<Favorite> addFavoritePlacePost({
    required String name,
    required String address,
    required String placeCategory,
    String? id,
  }) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/favorites/');

    // ID가 제공되지 않으면 자동 생성
    final favoriteId = id ?? 'place_${DateTime.now().millisecondsSinceEpoch}';

    final body = jsonEncode({
      'id': favoriteId,
      'type': 'place',
      'name': name,
      'address': address,
      'place_category': placeCategory,
      'bus_number': null,
      'station_name': null,
      'station_id': null,
    });

    final response = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Favorite.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('즐겨찾기 추가 실패: ${response.statusCode} ${response.body}');
    }
  }

  /// 즐겨찾기 추가 (버스)
  Future<Favorite> addFavoriteBus({
    required String id,
    required String name,
    required String busNumber,
  }) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/favorites/');

    final body = jsonEncode({
      'id': id,
      'type': 'bus',
      'name': name,
      'address': null,
      'place_category': null,
      'bus_number': busNumber,
      'station_name': null,
      'station_id': null,
    });

    final response = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Favorite.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('즐겨찾기 추가 실패: ${response.statusCode} ${response.body}');
    }
  }

  /// 즐겨찾기 추가 (정류장)
  Future<Favorite> addFavoriteBusStop({
    required String id,
    required String name,
    required String stationName,
    required String stationId,
  }) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/favorites/');

    final body = jsonEncode({
      'id': id,
      'type': 'busStop',
      'name': name,
      'address': null,
      'place_category': null,
      'bus_number': null,
      'station_name': stationName,
      'station_id': stationId,
    });

    final response = await http.post(
      uri,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Favorite.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('즐겨찾기 추가 실패: ${response.statusCode} ${response.body}');
    }
  }

  /// 즐겨찾기 삭제
  Future<void> removeFavorite(String favoriteId) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$_baseUrl/favorites/$favoriteId');

    final response = await http.delete(uri, headers: headers);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('즐겨찾기 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }
}
