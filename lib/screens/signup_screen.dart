import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _idController = TextEditingController();
  final _userNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pwController = TextEditingController();
  final _confirmPwController = TextEditingController();

  bool _obscureText = true;
  bool _obscureConfirmPw = true;

  @override
  void dispose() {
    _idController.dispose();
    _userNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final userId = _idController.text.trim();
    final userName = _userNameController.text.trim();
    final email = _emailController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final password = _pwController.text.trim();

    if (userId.isEmpty ||
        userName.isEmpty ||
        email.isEmpty ||
        phoneNumber.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 필드를 입력하세요')),
      );
      return;
    }

    if (password != _confirmPwController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 일치하지 않습니다')),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('http://13.125.127.75:8000/users/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "userId": userId,
          "userName": userName,
          "email": email,
          "phone_number": phoneNumber,
          "password": password,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원가입 성공! 로그인 화면으로 이동합니다.')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('회원가입 실패: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('에러 발생: $e')),
      );
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
                  '회원가입',
                  style: AppTextStyles.title1.copyWith(
                    color: AppColors.primary.s500,
                  ),
                ),
                const SizedBox(height: 40),

                // 아이디
                _buildTextField(
                  controller: _idController,
                  hintText: '아이디',
                ),

                // 이름
                _buildTextField(
                  controller: _userNameController,
                  hintText: '이름',
                ),

                // 이메일
                _buildTextField(
                  controller: _emailController,
                  hintText: '이메일',
                ),

                // 전화번호
                _buildTextField(
                  controller: _phoneController,
                  hintText: '전화번호',
                ),

                // 비밀번호
                _buildTextField(
                  controller: _pwController,
                  hintText: '비밀번호',
                  obscureText: _obscureText,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.grayscale.s500,
                    ),
                    onPressed: () =>
                        setState(() => _obscureText = !_obscureText),
                  ),
                ),

                // 비밀번호 확인
                _buildTextField(
                  controller: _confirmPwController,
                  hintText: '비밀번호 확인',
                  obscureText: _obscureConfirmPw,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPw
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.grayscale.s500,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPw = !_obscureConfirmPw;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // 회원가입 버튼
                GestureDetector(
                  onTap: _signup,
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.s500,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '회원가입',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title7.copyWith(
                        color: AppColors.grayscale.s30,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('이미 계정이 있으신가요?'),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        );
                      },
                      child: const Text('로그인'),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle:
              AppTextStyles.body2_1.copyWith(color: AppColors.grayscale.s500),
          filled: true,
          fillColor: AppColors.grayscale.s30,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.grayscale.s500, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.grayscale.s500, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.grayscale.s500, width: 2),
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}
