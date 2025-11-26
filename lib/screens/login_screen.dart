import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'main_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();

  // ✅ 보안 저장소
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool _obscureText = true;
  bool _isLoading = false;

  static const LOGIN_API_URL = "http://13.125.127.75:8000/users/login";
  static const KAKAO_LOGIN_API_URL = "실제 api 주소";

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  // ✅ 디버그 모드 버튼 동작 (유지)
  void _debug() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainScaffold(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _login() async {
    if (_isLoading) return;

    final id = _idController.text.trim();
    final pw = _pwController.text.trim();

    if (id.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("아이디와 비밀번호를 입력해주세요.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse(LOGIN_API_URL),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "grant_type": "password",
          "username": id,
          "password": pw,
          "scope": "",
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // ✅ 서버 응답에서 accessToken 추출
        final accessToken = data['access_token']?.toString();
        final tokenType = data['token_type']?.toString();

        if (accessToken == null || accessToken.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("로그인 응답에 accessToken이 없습니다.")),
          );
          return;
        }

        await _secure.write(key: 'access_token', value: accessToken);
        await _secure.write(key: 'token_type', value: tokenType ?? 'bearer');

        // ✅ 홈으로 이동
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainScaffold(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else if (response.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("아이디 또는 비밀번호가 올바르지 않습니다.")),
        );
      } else {
        final msg = (response.body.isNotEmpty)
            ? response.body
            : "code ${response.statusCode}";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("로그인 실패: $msg, ${response.statusCode}")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("로그인 에러: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grayscale.s30,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              children: [
                const SizedBox(height: 80),
                Text(
                  '환영합니다!',
                  style: AppTextStyles.title1
                      .copyWith(color: AppColors.primary.s500),
                ),
                const SizedBox(height: 40),

                // 아이디 입력
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: _idController,
                    decoration: InputDecoration(
                      hintText: '아이디',
                      hintStyle: AppTextStyles.body2_1
                          .copyWith(color: AppColors.grayscale.s500),
                      filled: true,
                      fillColor: AppColors.grayscale.s30,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 2),
                      ),
                    ),
                  ),
                ),

                // 비밀번호 입력
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: _pwController,
                    obscureText: _obscureText,
                    decoration: InputDecoration(
                      hintText: '비밀번호',
                      hintStyle: AppTextStyles.body2_1
                          .copyWith(color: AppColors.grayscale.s500),
                      filled: true,
                      fillColor: AppColors.grayscale.s30,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppColors.grayscale.s500, width: 2),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.grayscale.s500,
                        ),
                        onPressed: () =>
                            setState(() => _obscureText = !_obscureText),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 로그인 버튼
                GestureDetector(
                  onTap: _isLoading ? null : _login,
                  child: AbsorbPointer(
                    absorbing: _isLoading,
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.s500,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.grayscale.s30),
                            )
                          : Text(
                              '로그인',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.title7.copyWith(
                                  color: AppColors.grayscale.s30, height: 1.0),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ✅ 디버그 모드 버튼 (유지)
                GestureDetector(
                  onTap: _debug,
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.s500,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.grayscale.s30),
                          )
                        : Text(
                            '디버그 모드',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.title7.copyWith(
                                color: AppColors.grayscale.s30, height: 1.0),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // 소셜 로그인 버튼 (미구현)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SocialCircleButton(
                      backgroundColor: AppColors.secondary.s100,
                      onTap: () {}, // TODO: 카카오
                      child: Image.asset('lib/카카오톡.png', width: 40, height: 40),
                    ),
                    const SizedBox(width: 20),
                    _SocialCircleButton(
                      backgroundColor: AppColors.grayscale.s30,
                      border: Border.all(color: AppColors.grayscale.s500),
                      onTap: () {}, // TODO: 구글
                      child: Image.asset('lib/구글.png', width: 28, height: 28),
                    ),
                    const SizedBox(width: 20),
                    _SocialCircleButton(
                      backgroundColor: AppColors.grayscale.s30,
                      onTap: () {}, // TODO: 네이버
                      child: Image.asset('lib/네이버.png', width: 55, height: 55),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialCircleButton extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final Border? border;
  final VoidCallback onTap;

  const _SocialCircleButton({
    required this.child,
    required this.backgroundColor,
    required this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: border,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
