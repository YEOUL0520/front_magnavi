import 'dart:async'; // 🔸 Completer / nextFrame 용
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/custom_search_bar.dart';

import '1. home_screen.dart';
import '2. profile_screen.dart';

// 패널 콘텐츠
import 'panels/1. home_panel.dart' show HomePanel;
import 'panels/2. transport_panel.dart' show TransitPanel;
import 'panels/3. map_panel.dart' show NearbyPanel;
import 'panels/4. search_panel.dart'
    show DirectionsPanel, DirectionsPanelMode;

enum PanelType { home, transit, nearby, directions }

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // ---- Config ----
  static const double _peekSize = 0.08;     // 빼꼼
  static const double _expandedSize = 0.39; // 기본 펼침
  static const double _maxSize = 0.92;

  // 길찾기 패널 전용 권장 사이즈
  static const double _directionsSummarySize = 0.29;    // 결과 요약
  static const double _directionsNavigationSize = 0.23; // 내비 안내

  final _dragController = DraggableScrollableController();
  final ValueNotifier<double> _panelHeightPx = ValueNotifier<double>(0);

  int _currentIndex = 0;               // 하단바 선택
  PanelType _panel = PanelType.home;   // 기본 홈 패널
  bool _panelVisible = true;           // 프로필에선 숨김
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    _dragController.addListener(() {
      if (!_dragController.isAttached || !mounted) return;
      final h = MediaQuery.of(context).size.height;
      _panelHeightPx.value = _panelVisible ? (_dragController.size * h) : 0;
    });

    // ✅ 첫 프레임에서 피크 높이 반영
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = MediaQuery.of(context).size.height;
      _panelHeightPx.value = _panelVisible ? (h * _peekSize) : 0;
    });
  }

  // 🔸 한 프레임 대기
  Future<void> _nextFrame() async {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
    await c.future;
  }

  Future<void> _waitForAttach() async {
    while (!_dragController.isAttached) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  bool get _isAttached => _dragController.isAttached;
  bool get _isOpen => _isAttached && _dragController.size > _peekSize + 0.02;

  // 패널 접기
  Future<void> _collapseToPeek() async {
    if (!_panelVisible || !_dragController.isAttached) return;
    await _dragController.animateTo(
      _peekSize,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    setState(() {});
  }

  // 패널 펼치기 (기본)
  Future<void> _expandToDefault([PanelType? to]) async {
    if (to != null) setState(() => _panel = to);
    await _waitForAttach();
    await _dragController.animateTo(
      _expandedSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _toggleFor(PanelType type) async {
    if (_panel == type && _isOpen) {
      await _collapseToPeek();
    } else {
      await _expandToDefault(type);
    }
  }

  // 인덱스 → 패널 타입
  PanelType _panelForIndex(int i) {
    switch (i) {
      case 0:
        return PanelType.home;
      case 1:
        return PanelType.transit;
      case 2:
        return PanelType.nearby;
      case 3:
        return PanelType.directions;
      default:
        return PanelType.home;
    }
  }

  // 하단바 탭
  Future<void> _onTap(int i) async {
    // 프로필 탭: 패널 완전 숨김
    if (i == 4) {
      setState(() {
        _currentIndex = i;
        _panelVisible = false;
        _panelHeightPx.value = 0;
      });
      return;
    }

    final nextPanel = _panelForIndex(i);
    final wasHidden = !_panelVisible;
    final isSamePanel = (_panel == nextPanel) && _panelVisible;

    setState(() {
      _currentIndex = i;
      _panelVisible = true;
      _panel = nextPanel;
    });

    if (wasHidden) {
      await _nextFrame(); // attach 대기
    }

    if (isSamePanel) {
      if (_isOpen) {
        await _collapseToPeek();
      } else {
        await _expandToDefault();
      }
    } else {
      await _expandToDefault();
    }
  }

  bool get _showSearchBar => _currentIndex != 4;

  // 🔸 DirectionsPanel 이 모드 바꿀 때 패널 높이 조정
  void _onDirectionsModeChanged(DirectionsPanelMode mode) {
    if (_panel != PanelType.directions) return;
    if (!_dragController.isAttached) return;

    double target;
    switch (mode) {
      case DirectionsPanelMode.search:
        target = _expandedSize; // 검색 화면은 기존 기본 펼침
        break;
      case DirectionsPanelMode.summary:
        target = _directionsSummarySize; // 결과 요약 (스크린샷처럼 살짝만)
        break;
      case DirectionsPanelMode.navigation:
        target = _directionsNavigationSize; // 내비 안내는 더 작게
        break;
    }

    _dragController.animateTo(
      target,
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyIndex = (_currentIndex == 4) ? 1 : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (_panelVisible && _isOpen) {
          await _collapseToPeek();
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          final m = ScaffoldMessenger.of(context);
          m.hideCurrentSnackBar();
          m.showSnackBar(
            const SnackBar(
              content: Text('한 번 더 누르면 앱이 종료됩니다.'),
              duration: Duration(milliseconds: 1500),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.all(16),
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.grayscale.s30,
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              // 홈 / 내정보
              IndexedStack(
                index: bodyIndex,
                children: [
                  HomeScreen(
                    bottomInsetListenable: _panelHeightPx,
                    onRequestCollapsePanel: _collapseToPeek,
                  ),
                  const ProfileScreen(),
                ],
              ),

              if (_showSearchBar)
                SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 16, left: 20, right: 20),
                    child: CustomSearchBar(),
                  ),
                ),

              // 패널
              if (_panelVisible)
                _PeekablePanel(
                  controller: _dragController,
                  peekSize: _peekSize,
                  maxSize: _maxSize,
                  title: _titleFor(_panel),
                  contentBuilder: (sc) => _panelBody(_panel, sc),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(PanelType p) {
    switch (p) {
      case PanelType.home:
        return '홈';
      case PanelType.transit:
        return '대중교통';
      case PanelType.nearby:
        return '내 주변';
      case PanelType.directions:
        return '길찾기';
    }
  }

  Widget _panelBody(PanelType p, ScrollController sc) {
    switch (p) {
      case PanelType.home:
        return HomePanel(controller: sc);
      case PanelType.transit:
        return TransitPanel(controller: sc);
      case PanelType.nearby:
        return NearbyPanel(controller: sc);
      case PanelType.directions:
        return DirectionsPanel(
          controller: sc,
          onModeChanged: _onDirectionsModeChanged, // 👈 모드 콜백 연결
        );
    }
  }
}

class _PeekablePanel extends StatelessWidget {
  final DraggableScrollableController controller;
  final double peekSize;
  final double maxSize;
  final String title;
  final Widget Function(ScrollController) contentBuilder;

  const _PeekablePanel({
    required this.controller,
    required this.peekSize,
    required this.maxSize,
    required this.title,
    required this.contentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    const snapCandidates = <double>[0.08, 0.23, 0.29, 0.39, 0.5, 0.8];

    // 헤더 드래그 → 시트 높이로 변환
    void _onHeaderDragUpdate(DragUpdateDetails details) {
      if (!controller.isAttached) return;
      final h = MediaQuery.of(context).size.height;
      final dy = details.primaryDelta ?? 0.0; // +아래 / -위
      final current = controller.size;
      final target = (current - dy / h).clamp(peekSize, maxSize);
      controller.jumpTo(target);
    }

    // 드래그 종료 → 가까운 스냅으로
    void _onHeaderDragEnd(DragEndDetails details) {
      if (!controller.isAttached) return;
      final v = details.primaryVelocity ?? 0.0; // +아래 / -위
      double current = controller.size;

      double pick;
      if (v.abs() > 300) {
        if (v < 0) {
          // 위로 플릭 → 더 큰 스냅으로
          final ups =
              snapCandidates.where((s) => s > current).toList()..sort();
          pick = ups.isNotEmpty ? ups.first : current;
        } else {
          // 아래로 플릭 → 더 작은 스냅으로
          final downs =
              snapCandidates.where((s) => s < current).toList()..sort();
          pick = downs.isNotEmpty ? downs.last : current;
        }
      } else {
        // 속도 작으면 가장 가까운 스냅
        pick = snapCandidates.reduce(
          (a, b) =>
              (a - current).abs() < (b - current).abs() ? a : b,
        );
      }

      pick = pick.clamp(peekSize, maxSize);
      controller.animateTo(
        pick,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }

    return Positioned.fill(
      child: DraggableScrollableSheet(
        controller: controller,
        initialChildSize: peekSize,
        minChildSize: peekSize,
        maxChildSize: maxSize,
        snap: true,
        snapSizes: snapCandidates,
        builder: (context, scrollController) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.grayscale.s30,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.grayscale.s900.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Column(
                  children: [
                    // ✅ 헤더 전체(원래 높이 그대로)를 드래그 핸들로
                    GestureDetector(
                      behavior: HitTestBehavior.opaque, // 빈 여백도 터치 인식
                      onVerticalDragUpdate: _onHeaderDragUpdate,
                      onVerticalDragEnd: _onHeaderDragEnd,
                      child: SizedBox(
                        width: double.infinity, // 전체 폭 확보
                        child: Padding(
                          padding:
                              const EdgeInsets.only(top: 8, bottom: 6),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.grayscale.s900,
                                  borderRadius:
                                      BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                style: AppTextStyles.title6.copyWith(
                                  color: AppColors.grayscale.s900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: PrimaryScrollController(
                        controller: scrollController,
                        child: contentBuilder(scrollController),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
