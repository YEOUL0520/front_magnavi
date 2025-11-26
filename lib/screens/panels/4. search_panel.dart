import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:midas_project/theme/app_theme.dart';
import '../controllers/route_controller.dart';
import '../../services/place_search_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
// 🎨 AppColors
import 'package:midas_project/theme/app_colors.dart';

/// 길찾기 패널이 어떤 상태인지 부모(MainScaffold)에 알려주기 위한 모드
enum DirectionsPanelMode { search, summary, navigation }

class DirectionsPanel extends StatefulWidget {
  final ScrollController controller;

  /// 모드가 바뀔 때마다 호출됨 (검색/결과/내비)
  final ValueChanged<DirectionsPanelMode>? onModeChanged;

  const DirectionsPanel({
    super.key,
    required this.controller,
    this.onModeChanged,
  });

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel> {
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  NLatLng? _start;
  NLatLng? _end;

  bool _busy = false;
  bool _routeReady = false;
  int? _etaSec, _distM;

  // 👉 내비 전용 상태 (유지)
  bool _navigating = false;
  int _stepIndex = 0;
  final List<GuidanceStep> _steps = [];

  final appKey = dotenv.env['TMAP_APP_KEY'] ?? '';

  DirectionsPanelMode _mode = DirectionsPanelMode.search;

  // ✅ 공통 버튼 스타일
  ButtonStyle get _primaryButtonStyle => ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary.s500,
        foregroundColor: Colors.white,
        overlayColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

  ButtonStyle get _secondaryButtonStyle => ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary.s50,
        foregroundColor: AppColors.primary.s500,
        overlayColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

  @override
  void initState() {
    super.initState();
    _setMode(DirectionsPanelMode.search);
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _setMode(DirectionsPanelMode m) {
    if (_mode == m) return;
    _mode = m;
    widget.onModeChanged?.call(m);
  }

  // ===== 버튼 리플/애니메이션 제거 헬퍼 =====
  Widget _noSplash(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      child: child,
    );
  }

  Future<void> _openPlacePicker({required bool forStart}) async {
    final picked = await showModalBottomSheet<PlaceItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PlacePickerSheet(),
    );
    if (picked == null) return;

    if (!picked.hasCoords) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('좌표를 불러오지 못했습니다. 다시 시도하세요.')),
      );
      return;
    }

    setState(() {
      if (forStart) {
        _start = NLatLng(picked.lat!, picked.lng!);
        _startCtrl.text = picked.name;
      } else {
        _end = NLatLng(picked.lat!, picked.lng!);
        _endCtrl.text = picked.name;
      }
    });
  }

  Future<void> _searchRoute() async {
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('출발·도착지를 선택하세요.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _etaSec = null;
      _distM = null;
      _routeReady = false;
      _navigating = false;
      _steps.clear();
      _stepIndex = 0;
    });

    final url = Uri.parse('https://apis.openapi.sk.com/tmap/routes/pedestrian?version=1');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'appKey': appKey,
    };
    final body = jsonEncode({
      'startX': _start!.longitude,
      'startY': _start!.latitude,
      'endX': _end!.longitude,
      'endY': _end!.latitude,
      'reqCoordType': 'WGS84GEO',
      'resCoordType': 'WGS84GEO',
      'startName': _startCtrl.text,
      'endName': _endCtrl.text,
    });

    try {
      final resp = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode ~/ 100 != 2) {
        throw Exception('TMAP ${resp.statusCode}');
      }
      final geo = jsonDecode(resp.body) as Map<String, dynamic>;

      int? eta, dist;
      final feats = (geo['features'] as List?) ?? [];
      if (feats.isNotEmpty) {
        final p0 = feats.firstWhere(
          (f) =>
              (f['geometry']?['type'] == 'Point') &&
              (f['properties']?['turnType'] == 200),
          orElse: () => feats.first,
        );
        eta = (p0['properties']?['totalTime'] as num?)?.toInt();
        dist = (p0['properties']?['totalDistance'] as num?)?.toInt();
      }

      final path = <NLatLng>[];
      NLatLng? last;
      NLatLng? sp, ep;

      for (final f in feats) {
        final g = f['geometry'] as Map<String, dynamic>?;
        final p = f['properties'] as Map<String, dynamic>?;
        if (g == null) continue;

        if (g['type'] == 'LineString') {
          final coords = (g['coordinates'] as List?) ?? [];
          for (final c in coords) {
            if (c is! List || c.length < 2) continue;
            final lon = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            final pt = NLatLng(lat, lon);
            if (last == null ||
                last.latitude != pt.latitude ||
                last.longitude != pt.longitude) {
              path.add(pt);
              last = pt;
            }
          }
        } else if (g['type'] == 'Point' && p != null) {
          final coords = (g['coordinates'] as List?) ?? [];
          if (coords.length >= 2) {
            final lon = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final pt = NLatLng(lat, lon);
            if (p['turnType'] == 200) sp = pt;
            if (p['turnType'] == 201) ep = pt;
          }
        }
      }

      // 지도에 전체 경로 반영
      RouteController.I.setRoute(
        RoutePayload(
          path: path,
          start: sp ?? _start,
          end: ep ?? _end,
          etaSec: eta,
          distanceM: dist,
        ),
      );

      // 단계 구성 유지
      final builtSteps = _buildStepsFromFeatures(feats);
      setState(() {
        _etaSec = eta;
        _distM = dist;
        _routeReady = true;
        _steps
          ..clear()
          ..addAll(builtSteps);
        _stepIndex = 0;
      });

      _setMode(DirectionsPanelMode.summary);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('경로 요청 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    RouteController.I.clear();
    setState(() {
      _etaSec = null;
      _distM = null;
      _routeReady = false;
      _navigating = false;
      _steps.clear();
      _stepIndex = 0;
    });
    _setMode(DirectionsPanelMode.search);
  }

  // ===== 내비게이션 제어 (유지) =====

  void _startNavigation() {
    if (_steps.isEmpty) return;
    setState(() {
      _navigating = true;
      _stepIndex = 0;
    });
    _setMode(DirectionsPanelMode.navigation);
    _focusStepOnMap(_steps[_stepIndex]);
  }

  void _nextStep() {
    if (_stepIndex >= _steps.length - 1) return;
    setState(() => _stepIndex++);
    _focusStepOnMap(_steps[_stepIndex]);
  }

  void _prevStep() {
    if (_stepIndex == 0) return;
    setState(() => _stepIndex--);
    _focusStepOnMap(_steps[_stepIndex]);
  }

  void _endNavigation() {
    setState(() {
      _navigating = false;
      _stepIndex = 0;
    });
    _focusWholeRoute();
    _setMode(DirectionsPanelMode.summary);
  }

  void _focusStepOnMap(GuidanceStep s) {
    // 필요 시 RouteController 연결
    // RouteController.I.highlightSegment(s.polyline, target: s.focusPoint);
  }

  void _focusWholeRoute() {
    // RouteController.I.focusWhole();
  }

  // ===== 포맷터 =====

  String _fmtKoreanDuration(int? sec) {
    if (sec == null) return '시간 정보 없음';
    if (sec <= 0) return '1분 미만 소요';
    final h = Duration(seconds: sec).inHours;
    final ceilMinTotal = (sec / 60).ceil();
    final mOnly = ceilMinTotal - h * 60;
    if (h > 0 && mOnly > 0) return '${h}시간 ${mOnly}분 소요';
    if (h > 0 && mOnly == 0) return '${h}시간 소요';
    return '${ceilMinTotal}분 소요';
  }

  String _fmtTimeRangeFromNow(int? sec) {
    if (sec == null) return '';
    final now = DateTime.now();
    final end = now.add(Duration(seconds: sec));
    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${hhmm(now)}~${hhmm(end)}';
  }

  String _fmtDistance(int? m) {
    if (m == null) return '';
    return m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m} m';
  }

  // ===== GeoJSON → 단계(step) 빌더 (유지) =====
  List<GuidanceStep> _buildStepsFromFeatures(List feats) {
    final steps = <GuidanceStep>[];

    List<NLatLng> currentLine = [];
    Map<String, dynamic>? lastPointProp;
    NLatLng? lastPointCoord;

    NLatLng _toLatLng(List c) => NLatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());

    void _commitStepFromLastPoint() {
      if (lastPointProp == null) return;
      final desc = (lastPointProp!['description'] as String?)?.trim() ?? '';
      final turnType = (lastPointProp!['turnType'] as num?)?.toInt();
      final nearName = (lastPointProp!['nearPoiName'] as String?)?.trim();

      int? distanceM;
      int? timeSec;

      if (lastPointProp!.containsKey('_prevLine_distance')) {
        distanceM = lastPointProp!['_prevLine_distance'] as int?;
      }
      if (lastPointProp!.containsKey('_prevLine_time')) {
        timeSec = lastPointProp!['_prevLine_time'] as int?;
      }

      steps.add(
        GuidanceStep(
          description: desc.isEmpty ? '다음 안내' : desc,
          nearName: nearName?.isEmpty ?? true ? null : nearName,
          turnType: turnType,
          distanceM: distanceM,
          timeSec: timeSec,
          polyline: List<NLatLng>.from(currentLine),
          focusPoint: lastPointCoord,
        ),
      );
      currentLine.clear();
    }

    for (var i = 0; i < feats.length; i++) {
      final f = feats[i] as Map<String, dynamic>;
      final g = f['geometry'] as Map<String, dynamic>?;
      final p = f['properties'] as Map<String, dynamic>?;

      if (g == null) continue;
      final type = g['type'];

      if (type == 'Point') {
        _commitStepFromLastPoint();

        final coords = (g['coordinates'] as List?) ?? [];
        if (coords.length >= 2) {
          lastPointCoord = _toLatLng(coords);
        } else {
          lastPointCoord = null;
        }
        lastPointProp = Map<String, dynamic>.from(p ?? {});
      } else if (type == 'LineString') {
        final coords = (g['coordinates'] as List?) ?? [];
        for (final c in coords) {
          if (c is! List || c.length < 2) continue;
          currentLine.add(_toLatLng(c));
        }
        if (p != null && lastPointProp != null) {
          lastPointProp!['_prevLine_distance'] =
              (p['distance'] as num?)?.toInt();
          lastPointProp!['_prevLine_time'] =
              (p['time'] as num?)?.toInt();
        }
      }
    }

    _commitStepFromLastPoint();

    return steps.where((s) => s.description.isNotEmpty || s.polyline.isNotEmpty).toList(growable: false);
  }

  String _prettyInstruction(GuidanceStep s) {
    final tt = s.turnType;
    String turn = '';
    if (tt == 12) turn = '좌회전';
    else if (tt == 13) turn = '우회전';
    else if (tt == 200) turn = '출발';
    else if (tt == 201) turn = '도착';

    final base = s.description.isEmpty ? (turn.isEmpty ? '이동' : turn) : s.description;
    return base;
  }

  // ===== 공통 데코 =====

  InputDecoration _searchFieldDecoration({
    required String label,
    required IconData prefix, // (호출부 호환 위해 유지)
    required VoidCallback onTapSearch,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.grayscale.s600),
      hintStyle: TextStyle(color: AppColors.grayscale.s600.withOpacity(0.7)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.grayscale.s100, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.grayscale.s100, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.grayscale.s100, width: 1.3),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTapSearch,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Image.asset(
                'assets/images/magnifer.png',
                width: 20,
                height: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== 상단 닫기(X) 버튼 =====
  Widget _topRightCloseButton() {
    return SafeArea(
      top: true,
      bottom: false,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, right: 6),
          child: SizedBox(
            height: 28,
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              splashRadius: 18,
              icon: Icon(Icons.close_rounded, color: AppColors.grayscale.s600),
              onPressed: _endNavigation, // ← 내비게이션 종료
              tooltip: '길찾기 종료',
            ),
          ),
        ),
      ),
    );
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // === 내비 모드 ===
    if (_routeReady && _navigating) {
      final s = _steps.isEmpty ? null : _steps[_stepIndex];
      final isLast = _stepIndex >= _steps.length - 1;

      return Stack(
        children: [
          ListView(
            controller: widget.controller,
            padding: EdgeInsets.zero,
            children: [
              if (s != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단 정보 (거리/시간)
                      Row(
                        children: [
                          if (s.distanceM != null)
                            Text(
                              ' ${_fmtDistance(s.distanceM)}',
                              style: TextStyle(
                                color: AppColors.grayscale.s600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (s.timeSec != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· ${(s.timeSec! / 60).ceil()}분',
                              style: TextStyle(
                                color: AppColors.grayscale.s600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 안내 문구
                      Text(
                        _prettyInstruction(s),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),

              // 버튼 가로 배치 + 애니메이션 제거
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _noSplash(
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: _secondaryButtonStyle, // 이전 = 세컨더리
                          onPressed: _stepIndex > 0 ? _prevStep : null,
                          child: const Text('이전'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: isLast ? _secondaryButtonStyle : _primaryButtonStyle,
                          onPressed: isLast ? _endNavigation : _nextStep,
                          child: Text(isLast ? '종료' : '다음'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 🔸 패널 오른쪽 위 작은 X 버튼 (내비 모드에서만 표시)
          _topRightCloseButton(),
        ],
      );
    }

    // === 결과 요약 모드 ===
    if (_routeReady) {
      return ListView(
        controller: widget.controller,
        padding: EdgeInsets.zero,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 12, right: 8),
                    child: Text(
                      _fmtKoreanDuration(_etaSec),
                      style: AppTextStyles.title6.copyWith(color: AppColors.grayscale.s900)
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 14, left: 10),
                    child: Text(
                      _fmtTimeRangeFromNow(_etaSec),
                      style: AppTextStyles.body2_1.copyWith(
                        color: AppColors.grayscale.s600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    Icon(Icons.directions_walk,
                        size: 18, color: AppColors.grayscale.s700),
                    const SizedBox(width: 6),
                    Text(
                      '도보',
                      style: AppTextStyles.body2_1.copyWith(
                        color: AppColors.grayscale.s600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 출발/취소 가로 배치 + 애니메이션 제거
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _noSplash(
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: _primaryButtonStyle,
                          onPressed: _steps.isEmpty ? null : _startNavigation,
                          child: const Text('출발'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: _secondaryButtonStyle,
                          onPressed: _cancel,
                          child: const Text('취소'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // === 검색 모드 ===
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _startCtrl,
          readOnly: true,
          decoration: _searchFieldDecoration(
            label: '출발지 (장소/주소)',
            prefix: Icons.my_location_outlined,
            onTapSearch: () => _openPlacePicker(forStart: true),
          ),
          onTap: () => _openPlacePicker(forStart: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endCtrl,
          readOnly: true,
          decoration: _searchFieldDecoration(
            label: '도착지 (장소/주소)',
            prefix: Icons.flag_outlined,
            onTapSearch: () => _openPlacePicker(forStart: false),
          ),
          onTap: () => _openPlacePicker(forStart: false),
        ),
        const SizedBox(height: 12),
        // ✅ 경로 검색 버튼(메인 스타일) + 애니메이션 제거
        SizedBox(
          width: double.infinity,
          child: _noSplash(
            ElevatedButton(
              style: _primaryButtonStyle,
              onPressed: _busy ? null : _searchRoute,
              child: const Text('경로 검색'),
            ),
          ),
        ),
      ],
    );
  }
}

// ===== 모델 (유지) =====
class GuidanceStep {
  final String description; // "좌회전 후 76m 이동" 등
  final String? nearName;   // 근처 POI 명
  final int? turnType;      // 12/13/200/201 ...
  final int? distanceM;     // 직전 선분 거리
  final int? timeSec;       // 직전 선분 시간
  final List<NLatLng> polyline; // 이 단계에서 따라갈 선분
  final NLatLng? focusPoint;    // 안내 포커스 포인트

  GuidanceStep({
    required this.description,
    required this.nearName,
    required this.turnType,
    required this.distanceM,
    required this.timeSec,
    required this.polyline,
    required this.focusPoint,
  });
}

// ====== 장소 선택 바텀시트 (유지) ======
class _PlacePickerSheet extends StatefulWidget {
  const _PlacePickerSheet();

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final _q = TextEditingController();
  final _items = <PlaceItem>[];
  Timer? _debounce;
  bool _busy = false;
  int? _geocodingIndex;

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = v.trim();
      if (q.isEmpty) {
        setState(() => _items.clear());
        return;
      }

      setState(() {
        _busy = true;
        _geocodingIndex = null;
      });

      var results = await PlaceSearchService.searchKeyword(q, size: 15);
      if (results.isEmpty) {
        results = await PlaceSearchService.searchAddress(q);
      }

      setState(() {
        _items
          ..clear()
          ..addAll(results);
        _busy = false;
      });
    });
  }

  Future<void> _onTapItem(int index) async {
    final it = _items[index];
    if (it.hasCoords) {
      Navigator.of(context).pop(it);
      return;
    }

    final addr = it.address ?? it.name;
    setState(() => _geocodingIndex = index);

    final geo = await PlaceSearchService.geocodeAddress(addr, displayName: it.name);
    if (!mounted) return;

    setState(() => _geocodingIndex = null);

    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('좌표를 찾지 못했습니다. 다른 항목을 선택해보세요.')),
      );
      return;
    }

    Navigator.of(context).pop(geo);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '장소명 또는 주소를 입력하세요',
                  hintStyle:
                      TextStyle(color: AppColors.grayscale.s600.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.grayscale.s100, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.grayscale.s100, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.grayscale.s100, width: 1.3),
                  ),
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.grayscale.s200),
                itemBuilder: (_, i) {
                  final it = _items[i];
                  final subtitle =
                      it.address == null || it.address!.isEmpty
                          ? (it.hasCoords ? '좌표 확보됨' : null)
                          : it.address!;
                  final trailing = (_geocodingIndex == i)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (it.hasCoords
                          ? Icon(Icons.check_circle_outline,
                              color: AppColors.grayscale.s600)
                          : null);

                  return ListTile(
                    leading: Icon(Icons.place_outlined,
                        color: AppColors.grayscale.s700),
                    title: Text(it.name,
                        style: TextStyle(color: AppColors.grayscale.s800)),
                    subtitle: subtitle == null
                        ? null
                        : Text(subtitle,
                            style: TextStyle(color: AppColors.grayscale.s600)),
                    trailing: trailing,
                    onTap: () => _onTapItem(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
