import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart'; // debugPrint 위해 추가

class PlaceItem {
  final String name;      // 장소명 또는 도로명주소
  final String? address;  // 주소(도로명 or 지번)
  final double? lat;      // 선택 시 지오코딩으로 채움
  final double? lng;

  bool get hasCoords => lat != null && lng != null;

  const PlaceItem({
    required this.name,
    this.address,
    this.lat,
    this.lng,
  });

  PlaceItem copyWith({
    String? name,
    String? address,
    double? lat,
    double? lng,
  }) {
    return PlaceItem(
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }
}

class PlaceSearchService {
  // ====== (1) 네이버 OpenAPI - 장소명 검색 ======
  static const _openBase = 'https://openapi.naver.com';
  static String get _openClientId => dotenv.env['NAVER_OPEN_API_CLIENT_ID'] ?? '';
  static String get _openClientSecret => dotenv.env['NAVER_OPEN_API_CLIENT_SECRET'] ?? '';

  // ====== (2) 네이버 Cloud Platform - 지도 Geocoding ======
  static const _geoBase = 'https://maps.apigw.ntruss.com';
  static String get _geoKeyId => dotenv.env['NAVER_MAPS_API_KEY'] ?? '';
  static String get _geoKey   => dotenv.env['NAVER_MAPS_API_KEY_SECRET'] ?? '';

  static Map<String, String> get _geoHeaders => {
    'x-ncp-apigw-api-key-id': _geoKeyId,
    'x-ncp-apigw-api-key': _geoKey,
    'Accept': 'application/json',
  };

  // HTML 태그(<b>) 제거용
  static String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

  // ====== (A) 퍼블릭: 단건 주소 지오코딩 ======
  static Future<PlaceItem?> geocodeAddress(String address, {String? displayName}) async {
    if (address.trim().isEmpty) return null;
    final uri = Uri.parse("$_geoBase/map-geocode/v2/geocode")
        .replace(queryParameters: {'query': address});
    debugPrint('📡 [GEOCODE] 요청: ${uri.toString()}');
    debugPrint('🔑 Headers: $_geoHeaders');

    final res = await http.get(uri, headers: _geoHeaders);
    debugPrint('📥 [GEOCODE] 응답 코드: ${res.statusCode}');

    if (res.statusCode ~/ 100 != 2) {
      debugPrint('❌ [GEOCODE] 실패: ${res.body}');
      return null;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addrs = (data['addresses'] as List?) ?? [];
    debugPrint('📦 [GEOCODE] 결과 개수: ${addrs.length}');

    if (addrs.isEmpty) return null;
    final a = addrs.first;
    final lat = double.tryParse(a['y']?.toString() ?? '');
    final lng = double.tryParse(a['x']?.toString() ?? '');
    if (lat == null || lng == null) {
      debugPrint('⚠️ [GEOCODE] 좌표 파싱 실패');
      return null;
    }

    final road = (a['roadAddress'] as String?)?.trim();
    final jibun = (a['jibunAddress'] as String?)?.trim();
    final bestAddr = (road?.isNotEmpty == true ? road! : (jibun ?? address));

    debugPrint('✅ [GEOCODE] 변환 완료: $bestAddr ($lat, $lng)');

    return PlaceItem(
      name: displayName ?? bestAddr,
      address: bestAddr,
      lat: lat,
      lng: lng,
    );
  }

  // ====== (B) 주소 문자열 → 좌표 (그대로 유지) ======
  static Future<List<PlaceItem>> searchAddress(String query, {int size = 15}) async {
    if (query.trim().isEmpty) return [];
    debugPrint('🔎 [ADDR] 주소 검색: $query');
    final item = await geocodeAddress(query);
    return item == null ? [] : [item];
  }

  // ====== (C) 장소명 → (지오코딩 없이) 후보 리스트 ======
  static Future<List<PlaceItem>> searchKeyword(String query, {int size = 15}) async {
    if (query.trim().isEmpty) return [];
    debugPrint('🔍 [KEYWORD] 장소명 검색 시작: "$query"');

    final uri = Uri.parse("$_openBase/v1/search/local.json").replace(queryParameters: {
      'query': query,
      'display': '$size',
      'start': '1',
      'sort': 'random',
    });

    debugPrint('📡 [KEYWORD] 요청: ${uri.toString()}');

    final res = await http.get(uri, headers: {
      'X-Naver-Client-Id': _openClientId,
      'X-Naver-Client-Secret': _openClientSecret,
    });

    debugPrint('📥 [KEYWORD] 응답 코드: ${res.statusCode}');

    if (res.statusCode ~/ 100 != 2) {
      debugPrint('❌ [KEYWORD] 요청 실패: ${res.body}');
      return [];
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (data['items'] as List?) ?? [];
    debugPrint('📦 [KEYWORD] 검색 결과 개수: ${items.length}');

    if (items.isEmpty) return [];

    // 지오코딩 없이 후보만 구성
    final results = <PlaceItem>[];
    for (final it in items.take(size)) {
      final title = _stripTags((it['title'] as String?) ?? '').trim();
      final addr = ((it['roadAddress'] as String?) ?? (it['address'] as String?) ?? '').trim();
      if (title.isEmpty && addr.isEmpty) continue;

      results.add(PlaceItem(
        name: title.isNotEmpty ? title : (addr.isNotEmpty ? addr : query),
        address: addr.isNotEmpty ? addr : null,
        // lat/lng 는 비워둠 (선택 시 지오코딩)
      ));
    }
    return results;
  }
}
