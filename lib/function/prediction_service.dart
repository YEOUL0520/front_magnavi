import 'dart:convert';
import 'package:http/http.dart' as http;

/// 서버 바디에 지금은 PDR을 보내지 않지만,
/// SensorController 생성자에서 이미 사용 중이라 필드는 유지.
/// (서버 스키마 합의되면 toJson에 키만 추가)
class PredictRequest {
  final double magX;
  final double magY;
  final double magZ;
  final double oriAzimuth;
  final double oriPitch;
  final double oriRoll;

  // 클라 융합용 (현재 서버 전송 제외)
  final double pdrX;
  final double pdrY;
  final int stepCount;
  final double lastStepLength;

  PredictRequest({
    required this.magX,
    required this.magY,
    required this.magZ,
    required this.oriAzimuth,
    required this.oriPitch,
    required this.oriRoll,
    required this.pdrX,
    required this.pdrY,
    required this.stepCount,
    required this.lastStepLength,
  });

  Map<String, dynamic> toJson() {
    return {
      'Mag_X': magX,
      'Mag_Y': magY,
      'Mag_Z': magZ,
      'Ori_X': oriAzimuth,
      'Ori_Y': oriPitch,
      'Ori_Z': oriRoll,
      // 'PDR_X': pdrX,
      // 'PDR_Y': pdrY,
      // 'Step_Count': stepCount,
      // 'Last_Step_Length': lastStepLength,
    };
  }
}

class Predict {
  /// 서버의 prediction
  final int prediction;

  /// 서버 confidence (nullable)
  final double? confidence;

  /// 서버의 top_k_results를 **문자열 그대로** 보관
  final List<String> topKRaw;

  /// 기존 코드 호환용: result.num 로 접근 가능
  int get num => prediction;

  Predict({
    required this.prediction,
    required this.confidence,
    required this.topKRaw,
  });

  // 안전 캐스팅 헬퍼 (num 타입 사용 없이 구현)
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return double.tryParse(v.toString());
  }

  factory Predict.fromJson(Map<String, dynamic> json) {
    final List<String> topK =
        (json['top_k_results'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    return Predict(
      prediction: _toInt(json['prediction']),
      confidence: _toDoubleOrNull(json['confidence']),
      topKRaw: topK,
    );
  }
}

class PredictApi {
  static Future<Predict?> fetchPrediction(PredictRequest input) async {
    final url = Uri.parse('http://13.125.127.75:8000/predict');

    try {
      final response = await http.post(
        url,
        headers: const {
          'accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(input.toJson()),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Predict.fromJson(data);
      } else {
        print('요청 실패: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('에러 발생: $e');
    }
    return null;
  }
}
