import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'package:midas_project/function/location_service.dart';
import 'package:midas_project/services/favorite_service.dart';
import 'package:midas_project/models/favorite_model.dart';

class SlideUpCard extends StatefulWidget {
  final VoidCallback onClose;
  final String? markerId;

  const SlideUpCard({
    super.key,
    required this.onClose,
    this.markerId,
  });

  @override
  State<SlideUpCard> createState() => _SlideUpCardState();
}

class _SlideUpCardState extends State<SlideUpCard> {
  late final LocationService _locationService;
  final FavoriteService _favoriteService = FavoriteService();

  bool _isFavorite = false;
  bool _checkingFavorite = true;
  bool _processingFavorite = false;
  String? _favoriteId;

  @override
  void initState() {
    super.initState();

    // LocationService 인스턴스 확보
    try {
      _locationService = Get.find<LocationService>();
    } catch (_) {
      _locationService = Get.put(LocationService());
    }

    final mid = widget.markerId;
    if (mid != null && mid.isNotEmpty) {
      _locationService.setMarkerId(mid);
    }

    // 즐겨찾기 상태 확인
    _checkFavoriteStatus();
  }

  /// 즐겨찾기 상태 확인
  Future<void> _checkFavoriteStatus() async {
    if (widget.markerId == null) {
      setState(() => _checkingFavorite = false);
      return;
    }

    try {
      final favorites = await _favoriteService.getFavorites();

      // markerId로 즐겨찾기 찾기 (place 타입이면서 이름이나 주소가 markerId와 관련)
      final favorite = favorites.firstWhereOrNull((fav) =>
          fav.type == FavoriteType.place &&
          (fav.id.contains(widget.markerId!) || fav.name == widget.markerId));

      if (mounted) {
        setState(() {
          _isFavorite = favorite != null;
          _favoriteId = favorite?.id;
          _checkingFavorite = false;
        });
      }
    } catch (e) {
      debugPrint('즐겨찾기 상태 확인 실패: $e');
      if (mounted) {
        setState(() => _checkingFavorite = false);
      }
    }
  }

  /// 즐겨찾기 추가
  Future<void> _addFavorite() async {
    if (_processingFavorite) return;

    final location = _locationService.location.value;
    if (location == null) {
      _showSnackBar('위치 정보를 불러올 수 없습니다.');
      return;
    }

    setState(() => _processingFavorite = true);

    try {
      // 고유 ID 생성 (place_markerId_timestamp)
      final uniqueId =
          'place_${widget.markerId}_${DateTime.now().millisecondsSinceEpoch}';

      await _favoriteService.addFavoritePlacePost(
        id: uniqueId,
        name: location.locationName ?? widget.markerId ?? '위치',
        address: location.address,
        placeCategory:
            'work', // 'home', 'work', 'convenienceStore', 'school', 'etc' 중 하나
      );

      if (mounted) {
        setState(() {
          _isFavorite = true;
          _favoriteId = uniqueId;
          _processingFavorite = false;
        });
        _showSnackBar('즐겨찾기에 추가되었습니다.');
      }
    } catch (e) {
      debugPrint('즐겨찾기 추가 실패: $e');
      if (mounted) {
        setState(() => _processingFavorite = false);
        _showSnackBar('즐겨찾기 추가에 실패했습니다: $e');
      }
    }
  }

  /// 즐겨찾기 삭제
  Future<void> _removeFavorite() async {
    if (_processingFavorite || _favoriteId == null) return;

    // 삭제 확인 다이얼로그
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: const Text('즐겨찾기에서 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('삭제', style: TextStyle(color: AppColors.secondary.s700)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    setState(() => _processingFavorite = true);

    try {
      await _favoriteService.removeFavorite(_favoriteId!);

      if (mounted) {
        setState(() {
          _isFavorite = false;
          _favoriteId = null;
          _processingFavorite = false;
        });
        _showSnackBar('즐겨찾기에서 삭제되었습니다.');
      }
    } catch (e) {
      debugPrint('즐겨찾기 삭제 실패: $e');
      if (mounted) {
        setState(() => _processingFavorite = false);
        _showSnackBar('즐겨찾기 삭제에 실패했습니다: $e');
      }
    }
  }

  /// 즐겨찾기 토글
  void _toggleFavorite() {
    if (_isFavorite) {
      _removeFavorite();
    } else {
      _addFavorite();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final double bottomPadding = mediaQuery.padding.bottom;
    final double bottomInset = mediaQuery.viewInsets.bottom;
    final double navigationBarHeight = 58.0;
    final double totalBottomGap =
        bottomPadding + navigationBarHeight + bottomInset;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: EdgeInsets.only(bottom: totalBottomGap),
        height: 227,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.grayscale.s30,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.grayscale.s100, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Obx(() {
          final isLoading = _locationService.loading.value;
          final location = _locationService.location.value;
          final error = _locationService.error.value;

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("오류 발생", style: AppTextStyles.title6),
                    _buildStarButton(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  error,
                  style: AppTextStyles.body2_1
                      .copyWith(color: AppColors.grayscale.s600),
                ),
                const Spacer(),
                Center(
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: widget.onClose,
                  ),
                ),
              ],
            );
          }

          // 위치 정보 fallback
          final locationName = location?.locationName ?? "위치 정보 없음";
          final description = location?.description ?? "위치 설명이 없습니다.";
          final floor = location?.floor ?? 0;
          final address = location?.address ?? "주소 정보 없음";
          final markerIdLabel = widget.markerId ?? "-";

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address,
                          style: AppTextStyles.title6,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          (floor > 0)
                              ? "$floor층 | ID: $markerIdLabel"
                              : "ID: $markerIdLabel",
                          style: AppTextStyles.body2_1.copyWith(
                            color: AppColors.grayscale.s500,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildStarButton(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                locationName,
                style: AppTextStyles.body2_1.copyWith(
                  color: AppColors.grayscale.s500,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              const Expanded(child: SizedBox()),
              // 액션 버튼
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            // TODO: 출발 로직
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: AppColors.primary.s500,
                            foregroundColor: AppColors.grayscale.s30,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            "출발",
                            style: AppTextStyles.body1_3
                                .copyWith(color: AppColors.grayscale.s30),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            // TODO: 도착 로직
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: AppColors.primary.s50,
                            foregroundColor: AppColors.primary.s500,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            "도착",
                            style: AppTextStyles.body1_3
                                .copyWith(color: AppColors.primary.s500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: widget.onClose,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// 즐겨찾기 버튼 위젯
  Widget _buildStarButton() {
    if (_checkingFavorite) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_processingFavorite) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: _toggleFavorite,
      child: Image.asset(
        _isFavorite
            ? 'assets/images/fill_star.png'
            : 'assets/images/empty_star.png',
        width: 24,
        height: 24,
      ),
    );
  }
}
