import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:midas_project/theme/app_colors.dart';
import 'package:midas_project/theme/app_theme.dart';
import 'package:midas_project/screens/indoor_map_screen.dart';
import 'package:midas_project/screens/outdoor_map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.bottomInsetListenable,
    this.onRequestCollapsePanel,
  });

  /// 패널(또는 키보드) 높이를 px로 전달받아 버튼을 패널 위로 띄우는 용도
  final ValueListenable<double>? bottomInsetListenable;

  /// 마커 탭 시 외부에서 패널을 피크로 접어달라고 요청할 때 사용
  final Future<void> Function()? onRequestCollapsePanel;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isIndoorMode = false; // false = 실외, true = 실내

  @override
  Widget build(BuildContext context) {
    final ValueListenable<double> inset =
        widget.bottomInsetListenable ?? ValueNotifier<double>(0);

    return Scaffold(
      body: Stack(
        children: [
          // 지도 표시
          if (_isIndoorMode)
            SafeArea(
              child: IndoorMapScreen(
                bottomInsetListenable: widget.bottomInsetListenable,
                onRequestCollapsePanel: widget.onRequestCollapsePanel,
              ),
            )
          else
            const OutdoorMapScreen(),

          // 상단 실내/실외 전환 버튼
          Positioned(
            top: 80,
            right: 16,
            child: SafeArea(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.grayscale.s30,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.grayscale.s200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapToggleButton(
                        label: '실외',
                        icon: Icons.map,
                        isSelected: !_isIndoorMode,
                        onTap: () => setState(() => _isIndoorMode = false),
                      ),
                      Container(width: 1, height: 32, color: AppColors.grayscale.s200),
                      _MapToggleButton(
                        label: '실내',
                        icon: Icons.store,
                        isSelected: _isIndoorMode,
                        onTap: () => setState(() => _isIndoorMode = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 하단 현위치 버튼 (패널 높이에 맞춰 자동으로 위로 이동)
          ValueListenableBuilder<double>(
            valueListenable: inset,
            builder: (context, panelHeight, _) {
              // 패널 위로 12px 띄우되, 최소 48px 여백 유지
              final double dynamicBottom = math.max(48.0, panelHeight + 12.0);

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                right: 16,
                bottom: dynamicBottom,
                child: SafeArea(
                  left: false, top: false, right: false, bottom: true,
                  child: Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: AppColors.grayscale.s30,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        if (_isIndoorMode) {
                          IndoorMapScreenStateHolder.state?.centerToCurrentPosition();
                        } else {
                          OutdoorMapScreenStateHolder.state?.moveToCurrentLocation();
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.my_location, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ----------------------------
// 실내/실외 전환 버튼 위젯
// ----------------------------
class _MapToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.secondary.s800 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.grayscale.s30 : AppColors.grayscale.s600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.caption1_2.copyWith(
                color: isSelected ? AppColors.grayscale.s30 : AppColors.grayscale.s600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
