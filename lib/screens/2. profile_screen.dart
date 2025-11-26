import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:midas_project/api/api_client.dart';
import 'package:midas_project/models/favorite_model.dart';
import 'package:midas_project/services/favorite_service.dart';
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'auth_choice_screen.dart'; // ✅ 로그아웃 후 이동 화면

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 0=집/회사, 1=자주가는곳, 2=버스
  int selectedIndex = 0;

  final _favoriteService = FavoriteService();
  List<Favorite> _allFavorites = [];

  final ApiClient _apiClient = ApiClient();

  final _menus = const [
    ("home", "집/회사"),
    ("mappointwave", "자주가는곳"),
    ("bus", "버스"),
  ];

  // ---- 사용자 닉네임 로딩용 ----
  static const String _baseUrl = "http://13.125.127.75:8000";
  String? _userName;
  bool _isLoadingName = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadUserName();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await _favoriteService.getFavorites();
      if (mounted) {
        setState(() {
          _allFavorites = favorites;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('즐겨찾기 목록을 불러오는 데 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteFavorite(String id) async {
    // 1) 확인 다이얼로그
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('삭제'),
            content: const Text('삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('아니오'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('예'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    // 2) 삭제 + 새로고침
    try {
      await _favoriteService.removeFavorite(id);
      if (!mounted) return;
      await _loadFavorites();

      // 3) 성공 스낵바
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('즐겨찾기 삭제에 실패했습니다: $e')),
      );
    }
  }


  Future<void> _loadUserName() async {
    try {
      const secure = FlutterSecureStorage();
      final token = await secure.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _isLoadingName = false);
        return;
      }

      final res = await http.get(
        Uri.parse("$_baseUrl/users/me"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _userName = (data['userName'] ?? data['username'])?.toString();
          _isLoadingName = false;
        });
      } else {
        debugPrint("GET /users/me failed: ${res.statusCode} ${res.body}");
        setState(() => _isLoadingName = false);
      }
    } catch (e) {
      debugPrint("GET /users/me error: $e");
      if (mounted) setState(() => _isLoadingName = false);
    }
  }

  // ===== 로그아웃 처리 =====
  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('로그아웃'),
            content: const Text('로그아웃 하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('아니오'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('예'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldLogout) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    const secure = FlutterSecureStorage();
    await secure.delete(key: 'access_token');
    await secure.delete(key: 'token_type');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
      (_) => false,
    );
  }

  Future<void> _changeUserName(String nick) async {
    final text = nick.trim();
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임을 입력해주세요.')),
        );
      }
      return;
    }

    try {
      final res = await _apiClient.put(
        "/users/me/username",
        body: {"userName": text},
      );

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 204) {
        setState(() => _userName = text);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임이 변경되었습니다.')),
        );
      } else {
        debugPrint("PUT /users/me/username failed: ${res.statusCode} ${res.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('닉네임 변경 실패: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('닉네임 변경에 실패했습니다: $e')),
        );
      }
    }
  }

  // ===== 주소 등록 모달 열기 =====
  Future<void> _openAddAddressSheet() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddAddressSheet(),
    );

    if (!mounted) return;

    if (changed == true) {
      await _loadFavorites(); // ✅ 목록 리프레시
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('등록되었습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grayscale.s30,
      body: SafeArea(
        child: Column(
          children: [
            _ProfileHeader(
              userName: _isLoadingName ? null : (_userName ?? '로그인이 필요합니다.'),
              onTapSettings: _confirmLogout,
              onSubmitNickname: _changeUserName,
            ),
            Container(
              height: 60,
              padding: const EdgeInsets.only(left: 20, right: 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.grayscale.s100, width: 1.0),
                  bottom: BorderSide(color: AppColors.grayscale.s100, width: 1.0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_menus.length, (i) {
                  final item = _menus[i];
                  final isSelected = i == selectedIndex;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: i == _menus.length - 1 ? 0 : 36,
                    ),
                    child: _CategoryTab(
                      iconName: item.$1,
                      label: item.$2,
                      selected: isSelected,
                      onTap: () => setState(() => selectedIndex = i),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: _buildContent(selectedIndex),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(int index) {
    List<Favorite> filteredItems = [];
    String title = "";

    switch (index) {
      case 0: // 집/회사
        title = "즐겨찾기";
        filteredItems = _allFavorites.where((fav) {
          return fav.type == FavoriteType.place &&
              (fav.placeCategory == 'home' || fav.placeCategory == 'work');
        }).toList();
        break;
      case 1: // 자주가는곳
        title = "자주가는곳";
        filteredItems = _allFavorites.where((fav) {
          return fav.type == FavoriteType.place &&
              (fav.placeCategory != 'home' && fav.placeCategory != 'work');
        }).toList();
        break;
      case 2: // 버스/정류장
      default:
        title = "버스/정류장";
        filteredItems = _allFavorites.where((fav) {
          return fav.type == FavoriteType.bus || fav.type == FavoriteType.busStop;
        }).toList();
        break;
    }
    return _FavoriteList(
      title: title,
      items: filteredItems,
      onDelete: _deleteFavorite,
      onAddPressed: _openAddAddressSheet, // ✅ 모달 열기
    );
  }
}

/// ===== 상단 프로필 헤더 =====
class _ProfileHeader extends StatelessWidget {
  final String? userName;
  final VoidCallback onTapSettings;
  final Future<void> Function(String) onSubmitNickname;

  const _ProfileHeader({
    this.userName,
    required this.onTapSettings,
    required this.onSubmitNickname,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 8, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.grayscale.s500,
            child: Icon(Icons.person, color: AppColors.grayscale.s30),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              Text(
                userName ?? '불러오는 중...',
                style: AppTextStyles.title7
                    .copyWith(color: AppColors.grayscale.s900),
              ),
              IconButton(
                icon: Icon(Icons.edit, size: 18, color: AppColors.grayscale.s500),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) {
                      final controller = TextEditingController(text: userName);
                      return AlertDialog(
                        title: const Text("닉네임 수정"),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: "새 닉네임 입력",
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("취소"),
                          ),
                          TextButton(
                            onPressed: () async {
                              final text = controller.text.trim();
                              Navigator.pop(ctx);
                              await onSubmitNickname(text);
                            },
                            child: const Text("확인"),
                          ),
                        ],
                      );
                    },
                  );
                },
              )
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Image.asset('assets/images/bell.png', width: 24, height: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: Image.asset('assets/images/settings.png', width: 24, height: 24),
            onPressed: onTapSettings,
          ),
        ],
      ),
    );
  }
}

/// ===== 탭 버튼 =====
class _CategoryTab extends StatelessWidget {
  final String iconName;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.iconName,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        selected ? AppColors.grayscale.s900 : AppColors.grayscale.s500;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/${iconName}_${selected ? 'selected' : 'unselected'}.png',
              width: 24,
              height: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.caption2_2.copyWith(
                color: textColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===== 리스트 공통 위젯 =====
class _FavoriteList extends StatelessWidget {
  final String title;
  final List<Favorite> items;
  final Function(String) onDelete;
  final VoidCallback onAddPressed;

  const _FavoriteList({
    required this.title,
    required this.items,
    required this.onDelete,
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.grayscale.s30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 12),
            child: Text(
              title,
              style: AppTextStyles.title7
                  .copyWith(color: AppColors.grayscale.s900),
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.grayscale.s100),

          // 리스트
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                String smallText = item.name;
                String mainText = '';
                String itemIconName = 'mappointwave';

                if (item.type == FavoriteType.place) {
                  mainText = item.address ?? '주소 정보 없음';
                  itemIconName = (item.placeCategory == 'home' ||
                          item.placeCategory == 'work')
                      ? 'home'
                      : 'mappointwave';
                } else if (item.type == FavoriteType.bus) {
                  mainText = item.busNumber ?? '버스 번호 없음';
                  itemIconName = 'bus';
                } else if (item.type == FavoriteType.busStop) {
                  smallText = item.stationName ?? '정류장 이름 없음';
                  mainText = item.stationId ?? '정류장 번호 없음';
                  itemIconName = 'bus';
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/images/${itemIconName}_selected.png',
                            height: 24,
                            width: 24,
                            color: AppColors.grayscale.s900,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  smallText,
                                  style: AppTextStyles.caption2_1.copyWith(
                                    color: AppColors.grayscale.s500,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  mainText,
                                  style: AppTextStyles.body1_1.copyWith(
                                    color: AppColors.grayscale.s900,
                                    height: 1.4,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: AppColors.grayscale.s500, size: 20),
                            onPressed: () => onDelete(item.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.grayscale.s100,
                    ),
                  ],
                );
              },
            ),
          ),

          // 하단 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.grayscale.s200),
                  backgroundColor: AppColors.grayscale.s100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onAddPressed,
                child: Text(
                  "주소 등록하기",
                  style: AppTextStyles.title7
                      .copyWith(color: AppColors.grayscale.s900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------- 모달 바텀시트: 주소 등록 -------------------- */

enum PlaceKind { home, work, custom }

class AddAddressSheet extends StatefulWidget {
  const AddAddressSheet({super.key});

  @override
  State<AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<AddAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();          // “우리집”, “회사”, “단골카페”
  final _addressCtrl = TextEditingController();        // 주소
  final _customCatCtrl = TextEditingController();      // 자주가는곳 카테고리 텍스트

  PlaceKind _kind = PlaceKind.home;                    // 기본값: 집
  bool _submitting = false;

  final _favoriteService = FavoriteService();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _customCatCtrl.dispose();
    super.dispose();
  }

  String _resolvePlaceCategory() {
    switch (_kind) {
      case PlaceKind.home:
        return 'home';
      case PlaceKind.work:
        return 'work';
      case PlaceKind.custom:
        return _customCatCtrl.text.trim();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_kind == PlaceKind.custom && _customCatCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자주가는곳 이름을 입력하세요.')),
      );
      return;
    }

    final placeCategory = _resolvePlaceCategory();

    if (_kind == PlaceKind.custom &&
        (placeCategory == 'home' || placeCategory == 'work')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자주가는곳 이름은 home/work가 될 수 없어요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // ✅ 스웨거 스키마대로 POST (버스/정류장 3개는 null)
      await _favoriteService.addFavoritePlacePost(
        name: _labelCtrl.text.trim(),       // 별칭
        address: _addressCtrl.text.trim(),  // 주소
        placeCategory: placeCategory,       // home/work/사용자입력
      );

      if (!mounted) return;
      Navigator.pop(context, true); // ✅ 부모로 성공 신호
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('주소 등록 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom; // 키보드 높이
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        padding: EdgeInsets.only(bottom: inset),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Material(
            color: AppColors.grayscale.s30,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 헤더
                      Row(
                        children: [
                          Text('주소 등록',
                              style: AppTextStyles.title6
                                  .copyWith(color: AppColors.grayscale.s900)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 표시 이름
                      Text('표시 이름',
                          style: AppTextStyles.caption2_1
                              .copyWith(color: AppColors.grayscale.s500)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _labelCtrl,
                        decoration: InputDecoration(
                          hintText: '예) 우리집, 회사, 단골카페',
                          filled: true,
                          fillColor: AppColors.grayscale.s30,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '표시 이름을 입력하세요.' : null,
                      ),
                      const SizedBox(height: 14),

                      // 주소
                      Text('주소',
                          style: AppTextStyles.caption2_1
                              .copyWith(color: AppColors.grayscale.s500)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _addressCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: '도로명/지번 등 상세 주소',
                          filled: true,
                          fillColor: AppColors.grayscale.s30,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '주소를 입력하세요.' : null,
                      ),
                      const SizedBox(height: 16),

                      // 카테고리(집/회사/자주가는곳)
                      Text('카테고리',
                          style: AppTextStyles.caption2_1
                              .copyWith(color: AppColors.grayscale.s500)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('집'),
                            selected: _kind == PlaceKind.home,
                            onSelected: (_) => setState(() => _kind = PlaceKind.home),
                          ),
                          ChoiceChip(
                            label: const Text('회사'),
                            selected: _kind == PlaceKind.work,
                            onSelected: (_) => setState(() => _kind = PlaceKind.work),
                          ),
                          ChoiceChip(
                            label: const Text('자주가는곳'),
                            selected: _kind == PlaceKind.custom,
                            onSelected: (_) => setState(() => _kind = PlaceKind.custom),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 자주가는곳 이름 (custom일 때만)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: (_kind == PlaceKind.custom)
                            ? Column(
                                key: const ValueKey('custom-field'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('자주가는곳 이름',
                                      style: AppTextStyles.caption2_1
                                          .copyWith(color: AppColors.grayscale.s500)),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _customCatCtrl,
                                    decoration: InputDecoration(
                                      hintText: '예) 카페, 헬스장, 본가',
                                      filled: true,
                                      fillColor: AppColors.grayscale.s30,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 20),

                      // 저장 버튼
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.grayscale.s900,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _submitting
                              ? SizedBox(
                                  height: 22, width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.grayscale.s30),
                                )
                              : Text('저장',
                                  style: AppTextStyles.title7.copyWith(color: AppColors.grayscale.s30)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}