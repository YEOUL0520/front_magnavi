import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:midas_project/api/api_client.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'package:midas_project/screens/auth_choice_screen.dart';
import 'package:midas_project/screens/main_scaffold.dart';
import 'package:midas_project/function/sensor_controller.dart';
import 'package:midas_project/function/location_service.dart';

import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ .env 파일 로드
  await dotenv.load(fileName: ".env");
  

  // ✅ Kakao SDK 초기화 (.env에서 읽어오기)
  final kakaoNativeAppKey = dotenv.env['KAKAO_NATIVE_APP_KEY'];
  if (kakaoNativeAppKey == null || kakaoNativeAppKey.isEmpty) {
    debugPrint("❌ KAKAO_NATIVE_APP_KEY 누락됨 — .env 파일을 확인하세요.");
  } else {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }

  // ✅ NaverMap SDK 초기화 (.env에서 읽어오기)
  final naverClientId = dotenv.env['NAVER_MAPS_API_KEY'];

  if (naverClientId == null || naverClientId.isEmpty) {
    debugPrint("❌ NAVER_MAPS_API_KEY 누락됨 — .env 파일을 확인하세요.");
  } else {
    try {
      await FlutterNaverMap().init(
        clientId: naverClientId,
  
        onAuthFailed: (ex) {
          debugPrint("❌ 네이버맵 인증 실패: $ex");
        },
      );
      debugPrint("✅ NaverMap SDK initialized successfully");
    } catch (e) {
      debugPrint("❌ NaverMap SDK 초기화 오류: $e");
    }
  }

  // ✅ GetX 컨트롤러 초기화
  Get.put(SensorController());
  Get.put(LocationService());
  debugPrint("✅ GetX 컨트롤러 초기화 완료");

  runApp(const MyApp());
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Login UI',
      theme: appThemeData,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

/// ✅ 부팅 시 토큰 검사 후 자동 라우팅
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _secure = const FlutterSecureStorage();
  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// ✅ 사용자 토큰 검사 → 자동 라우팅
  Future<void> _bootstrap() async {
    try {
      final res = await _apiClient.get("/users/me");

      if (!mounted) return;

      if (res.statusCode == 200) {
        // 유효한 토큰 → 메인으로 이동
        _go(const MainScaffold());
      } else {
        // 만료된 토큰 → 삭제 후 로그인 화면으로
        await _clearToken();
        _go(const AuthChoiceScreen());
      }
    } catch (e) {
      if (!mounted) return;
      await _clearToken();
      _go(const AuthChoiceScreen());
    }
  }

  Future<void> _clearToken() async {
    await _secure.delete(key: 'access_token');
    await _secure.delete(key: 'token_type');
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (_) => false,
    );
  }

  


  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
