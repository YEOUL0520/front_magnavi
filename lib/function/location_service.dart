// 서버 통신용 (네트워크 + DTO)
import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// ===== DTO =====
class LocationDto {
  final String id; // 🔧 int → String
  final String? locationName;
  final String? description;
  final int floor;
  final String address;

  const LocationDto({
    required this.id,
    required this.locationName,
    required this.description,
    required this.floor,
    required this.address,
  });

  factory LocationDto.fromJson(Map<String, dynamic> j) {
    return LocationDto(
      id: j['id'].toString(), // 🔧 안전하게 문자열 변환
      locationName: j['location_name'] as String?,
      description: j['description'] as String?,
      floor: (j['floor'] as num?)?.toInt() ?? 0,
      address: j['address'] as String? ?? '',
    );
  }
}

/// ===== 서비스 (GetX Controller) =====
/// - markerId 변화 감지 → 자동 조회
/// - 캐시/TTL 내장
class LocationService extends GetxController {
  static const String _base = 'http://13.125.127.75:8000';
  static const Duration _timeout = Duration(seconds: 6);
  static const Duration _ttl = Duration(minutes: 5);

  final RxnString markerId = RxnString(); // 🔧 RxnInt → RxnString
  final RxBool loading = false.obs;
  final Rxn<LocationDto> location = Rxn<LocationDto>();
  final RxnString error = RxnString();

  // 캐시 및 타임스탬프 관리 (id: String 키)
  final Map<String, LocationDto> _cacheById = {};
  final Map<String, DateTime> _lastFetchedAt = {};

  @override
  void onInit() {
    // markerId 변경 자동 감지 → 조회
    ever<String?>(markerId, (id) async {
      if (id == null || id.isEmpty) {
        location.value = null;
        return;
      }
      await _loadById(id);
    });
    super.onInit();
  }

  /// 외부에서 marker ID 설정
  void setMarkerId(String? id) => markerId.value = id;

  /// 캐시 우선 조회 (만료 시 서버 호출)
  Future<void> _loadById(String id) async {
    loading.value = true;
    error.value = null;

    try {
      final now = DateTime.now();
      final lastFetched = _lastFetchedAt[id];
      final isFresh = lastFetched != null && now.difference(lastFetched) < _ttl;

      // 캐시가 신선하면 그대로 사용
      if (isFresh && _cacheById.containsKey(id)) {
        location.value = _cacheById[id];
        return;
      }

      // 서버에서 조회
      final fetched = await fetchByIdDirect(id);
      if (fetched != null) {
        location.value = fetched;
      } else {
        error.value = '해당 위치(id=$id)를 찾을 수 없음';
        location.value = null;
      }
    } catch (e) {
      error.value = e.toString();
      location.value = null;
    } finally {
      loading.value = false;
    }
  }

  /// 단일 위치 정보 API 호출
  Future<LocationDto?> fetchByIdDirect(String id) async {
    final uri = Uri.parse('$_base/locations/$id');
    final res = await http
        .get(uri, headers: {'accept': 'application/json'}).timeout(_timeout);

    if (res.statusCode == 200) {
      final dto = LocationDto.fromJson(jsonDecode(res.body));
      _cacheById[id] = dto;
      _lastFetchedAt[id] = DateTime.now();
      return dto;
    } else if (res.statusCode == 404) {
      return null;
    } else {
      throw Exception('GET $uri failed: ${res.statusCode}');
    }
  }
}
