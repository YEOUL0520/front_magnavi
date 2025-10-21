import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../controllers/route_controller.dart';
import '../../services/place_search_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DirectionsPanel extends StatefulWidget {
  final ScrollController controller;
  const DirectionsPanel({super.key, required this.controller});

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel> {
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  NLatLng? _start; // 선택된 출발 좌표
  NLatLng? _end;   // 선택된 도착 좌표

  bool _busy = false;
  bool _routeReady = false; // 결과 모드/검색 모드 전환
  int? _etaSec, _distM;

  final appKey = dotenv.env['TMAP_APP_KEY'] ?? '';

  @override
  void dispose() { _startCtrl.dispose(); _endCtrl.dispose(); super.dispose(); }

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
    setState(() { _busy = true; _etaSec = null; _distM = null; _routeReady = false; });

    final url = Uri.parse('https://apis.openapi.sk.com/tmap/routes/pedestrian?version=1');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'appKey': appKey,
    };
    final body = jsonEncode({
      'startX': _start!.longitude, 'startY': _start!.latitude,
      'endX':   _end!.longitude,   'endY':   _end!.latitude,
      'reqCoordType': 'WGS84GEO', 'resCoordType': 'WGS84GEO',
      'startName': _startCtrl.text, 'endName': _endCtrl.text,
    });

    try {
      final resp = await http.post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode ~/ 100 != 2) {
        throw Exception('TMAP ${resp.statusCode}');
      }
      final geo = jsonDecode(resp.body) as Map<String, dynamic>;

      int? eta, dist;
      final feats = (geo['features'] as List?) ?? [];
      if (feats.isNotEmpty) {
        final p0 = feats.firstWhere(
          (f) => (f['geometry']?['type'] == 'Point') &&
                 (f['properties']?['turnType'] == 200),
          orElse: () => feats.first,
        );
        eta  = (p0['properties']?['totalTime'] as num?)?.toInt();
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
            if (last == null || last.latitude != pt.latitude || last.longitude != pt.longitude) {
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

      RouteController.I.setRoute(
        RoutePayload(path: path, start: sp ?? _start, end: ep ?? _end, etaSec: eta, distanceM: dist),
      );

      setState(() {
        _etaSec = eta;
        _distM = dist;
        _routeReady = true;
      });
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
    });
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

    // 결과 모드: 배경/패딩 제거
    if (_routeReady) {
      return ListView(
        controller: widget.controller,
        padding: EdgeInsets.zero, // 🔥 바깥 패딩 제거
        children: [
          // 🔥 Card/Container 없이 바로 내용 렌더
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: "5분 소요   08:15~08:20"
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 12, right: 8), // 최소한의 좌우 여백만
                    child: Text(
                      _fmtKoreanDuration(_etaSec),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _fmtTimeRangeFromNow(_etaSec),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // 중간: 보행 아이콘 + "도보 · 거리"
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '도보${_distM == null ? '' : ' · ${_fmtDistance(_distM)}'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // 하단 버튼들(전체 폭, 여백 최소)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: null, // 비활성
                        child: const Text('출발'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancel,
                        child: const Text('취소'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 검색 모드
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _startCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: '출발지 (장소/주소)',
            prefixIcon: const Icon(Icons.my_location_outlined),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _openPlacePicker(forStart: true),
            ),
            border: const OutlineInputBorder(),
          ),
          onTap: () => _openPlacePicker(forStart: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: '도착지 (장소/주소)',
            prefixIcon: const Icon(Icons.flag_outlined),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _openPlacePicker(forStart: false),
            ),
            border: const OutlineInputBorder(),
          ),
          onTap: () => _openPlacePicker(forStart: false),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _searchRoute,
                icon: const Icon(Icons.route),
                label: const Text('경로 검색'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: const Icon(Icons.clear_all),
                label: const Text('초기화'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 장소/주소 검색 모달 시트
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
      if (q.isEmpty) { setState(() => _items.clear()); return; }

      setState(() { _busy = true; _geocodingIndex = null; });

      var results = await PlaceSearchService.searchKeyword(q, size: 15);
      if (results.isEmpty) {
        results = await PlaceSearchService.searchAddress(q);
      }

      setState(() {
        _items..clear()..addAll(results);
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
  void dispose() { _debounce?.cancel(); _q.dispose(); super.dispose(); }

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
              width: 44, height: 4,
              decoration: BoxDecoration(
                color: Colors.black26, borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '장소명 또는 주소를 입력하세요',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
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
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i];
                  final subtitle = it.address == null || it.address!.isEmpty
                      ? (it.hasCoords ? '좌표 확보됨' : null)
                      : it.address!;
                  final trailing = (_geocodingIndex == i)
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : (it.hasCoords ? const Icon(Icons.check_circle_outline) : null);

                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(it.name),
                    subtitle: subtitle == null ? null : Text(subtitle),
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
