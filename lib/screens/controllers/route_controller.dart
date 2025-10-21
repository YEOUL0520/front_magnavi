import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class RoutePayload {
  final List<NLatLng> path;
  final NLatLng? start;
  final NLatLng? end;
  final int? etaSec; // 소요시간(초)
  final int? distanceM;
  RoutePayload({
    required this.path,
    this.start,
    this.end,
    this.etaSec,
    this.distanceM,
  });
}

class RouteController extends ChangeNotifier {
  RouteController._();
  static final RouteController _i = RouteController._();
  static RouteController get I => _i;

  RoutePayload? _route;
  bool _clearRequested = false;

  RoutePayload? get route => _route;
  bool get clearRequested => _clearRequested;

  void setRoute(RoutePayload payload) {
    _route = payload;
    _clearRequested = false;
    notifyListeners();
  }

  void clear() {
    _route = null;
    _clearRequested = true;
    notifyListeners();
  }
}
