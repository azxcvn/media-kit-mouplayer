import 'package:flutter/material.dart';

/// 手势指示器类型（音量 / 亮度）
enum GestureIndicatorKind { volume, brightness }

/// 音量 / 亮度手势指示器（kazumi 风格现代化垂直样式）。
///
/// 设计对齐 kt 项目的 `ModernGestureIndicator`：
/// 圆角半透明深色胶囊 + 图标（按档位切换，带 Crossfade）+
/// 垂直胶囊进度条（底部填充，数值变化带缓动动画）+ 百分比文字。
/// 进出场动画由调用方（播放页 AnimatedSwitcher，音量从左滑入、
/// 亮度从右滑入）负责，本组件只承载内容与数值动画。
class PlayerGestureIndicator extends StatelessWidget {
  final GestureIndicatorKind kind;

  /// 音量 0 – 100；亮度 0 – 1
  final double value;

  const PlayerGestureIndicator({
    super.key,
    required this.kind,
    required this.value,
  });

  IconData get _icon {
    switch (kind) {
      case GestureIndicatorKind.volume:
        final v = value;
        if (v <= 0) return Icons.volume_off_rounded;
        if (v <= 33) return Icons.volume_mute_rounded;
        if (v <= 66) return Icons.volume_down_rounded;
        return Icons.volume_up_rounded;
      case GestureIndicatorKind.brightness:
        final v = value;
        if (v <= 0.33) return Icons.brightness_5;
        if (v <= 0.66) return Icons.brightness_6;
        return Icons.brightness_7;
    }
  }

  Color get _fillColor => switch (kind) {
        GestureIndicatorKind.volume => const Color(0xFF4FC3F7),
        GestureIndicatorKind.brightness => const Color(0xFFFFB74D),
      };

  double get _progress => switch (kind) {
        GestureIndicatorKind.volume => (value / 100).clamp(0.0, 1.0),
        GestureIndicatorKind.brightness => value.clamp(0.0, 1.0),
      };

  String get _text => switch (kind) {
        GestureIndicatorKind.volume =>
          '${value.round().clamp(0, 100)}%',
        GestureIndicatorKind.brightness =>
          '${(value * 100).round().clamp(0, 100)}%',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // 图标（按档位 Crossfade）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation,
                  child: child,
                ),
              ),
              child: Icon(
                _icon,
                key: ValueKey(_icon),
                size: 26,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            // 垂直胶囊进度条（底部向上填充，数值变化缓动）
            SizedBox(
              width: 8,
              height: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.2),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _progress),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, p, _) => Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: p.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _fillColor,
                            borderRadius: BorderRadius.circular(4),
                            // 顶部微光，增加质感
                            boxShadow: [
                              BoxShadow(
                                color: _fillColor.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 百分比文字
            Text(
              _text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
    );
  }
}
