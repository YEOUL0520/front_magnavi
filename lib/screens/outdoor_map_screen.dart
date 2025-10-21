import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'controllers/route_controller.dart';

class OutdoorMapScreenStateHolder {
  static _OutdoorMapScreenState? state;
}

class OutdoorMapScreen extends StatefulWidget {
  const OutdoorMapScreen({super.key});

  @override
  State<OutdoorMapScreen> createState() => _OutdoorMapScreenState();
}

class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  NaverMapController? _controller;
  bool _mapInitialized = false;
  bool _isLoading = true;

  bool _hasRoute = false;
  StreamSubscription<Position>? _posSub;

  static const _initialPos = NLatLng(35.8355, 128.7537); // 영남대
  static const _initialZoom = 15.0;

  @override
  void initState() {
    super.initState();
    OutdoorMapScreenStateHolder.state = this;
    _initLocationPermission();
    RouteController.I.addListener(_onRouteEvent);
  }

  @override
  void dispose() {
    RouteController.I.removeListener(_onRouteEvent);
    OutdoorMapScreenStateHolder.state = null;
    _posSub?.cancel();
    _controller = null;
    super.dispose();
  }

  Future<void> _initLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('위치 서비스 비활성화');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('위치 권한 거부됨');
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('위치 권한 영구 거부됨');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('위치 권한 확인 오류: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('위치 불러오기 실패: $e');
      return null;
    }
  }

  // HomeScreen의 공용 현위치 버튼이 호출
  Future<void> moveToCurrentLocation() async {
    final pos = await _getCurrentPosition();
    if (pos != null && _controller != null) {
      await _controller!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(pos.latitude, pos.longitude),
          zoom: 16,
        ),
      );
    } else {
      debugPrint('현재 위치 정보 없음 또는 컨트롤러 미초기화');
    }
  }

  Future<void> _onMapReady(NaverMapController controller) async {
    if (_mapInitialized) return;
    _controller = controller;
    _mapInitialized = true;

    try {
      final overlay = await _controller!.getLocationOverlay();
      overlay.setIsVisible(true);
      overlay.setCircleColor(const Color(0x59FF9800)); // ~35% 알파
      overlay.setCircleOutlineColor(const Color(0xFFFFB74D));
      overlay.setCircleOutlineWidth(2.0);

      final p0 = await _getCurrentPosition();
      if (p0 != null) {
        overlay.setPosition(NLatLng(p0.latitude, p0.longitude));
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((pos) async {
        try {
          final o = await _controller?.getLocationOverlay();
          o?.setPosition(NLatLng(pos.latitude, pos.longitude));
        } catch (e) {
          debugPrint('오버레이 위치 갱신 오류: $e');
        }
      });
    } catch (e) {
      debugPrint('오버레이 설정 오류: $e');
    }
  }

  Future<void> _onRouteEvent() async {
    if (_controller == null) return;

    if (RouteController.I.clearRequested) {
      await _controller!.clearOverlays();
      await _controller!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _initialPos, zoom: _initialZoom),
      );
      if (mounted) setState(() => _hasRoute = false);
      return;
    }

    final payload = RouteController.I.route;
    if (payload == null || payload.path.isEmpty) return;

    await _controller!.clearOverlays();

    final overlays = <NAddableOverlay>{
      if (payload.start != null)
        NMarker(id: 'start', position: payload.start!, caption: const NOverlayCaption(text: '출발')),
      if (payload.end != null)
        NMarker(id: 'end', position: payload.end!, caption: const NOverlayCaption(text: '도착')),
      NPolylineOverlay(id: 'route', coords: payload.path, width: 6, color: Colors.blue),
    };

    await _controller!.addOverlayAll(overlays);

    final b = _boundsFrom(payload.path);
    if (b != null) {
      await _controller!.updateCamera(
        NCameraUpdate.fitBounds(b, padding: const EdgeInsets.all(48)),
      );
    }

    if (mounted) setState(() => _hasRoute = true);
  }

  NLatLngBounds? _boundsFrom(List<NLatLng> coords) {
    if (coords.isEmpty) return null;
    double minLat = coords.first.latitude, maxLat = coords.first.latitude;
    double minLng = coords.first.longitude, maxLng = coords.first.longitude;
    for (final p in coords) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return NLatLngBounds(
      southWest: NLatLng(minLat, minLng),
      northEast: NLatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          NaverMap(
            onMapReady: _onMapReady,
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _initialPos,
                zoom: _initialZoom,
              ),
              indoorEnable: false,
              locationButtonEnable: false, // ❌ 기본 버튼 끔 — HomeScreen 공용 버튼만 사용
              consumeSymbolTapEvents: false,
            ),
          ),

          if (_hasRoute)
            Positioned(
              left: 12,
              top: MediaQuery.of(context).padding.top + 12,
              child: const Chip(
                avatar: Icon(Icons.route_outlined, size: 18),
                label: Text('경로 표시 중'),
              ),
            ),
        ],
      ),
    );
  }
}
