import 'package:flutter/material.dart';
import 'package:moumou/pages/player/player_metrics.dart';

/// 全宽进度条（自定义绘制，替代 Material Slider）：
/// 拖动实时预览目标时间，松手/点击跳转。
///
/// 为什么不用 Slider（历史坑，勿改回）：
/// - Material Slider 的轨道默认内缩（thumb/overlay 半径，约 14px），
///   轨道起点无法与返回箭头/时间/下一集精确对齐到 [kPlayerLeftInset]；
/// - 拖动/点击判定受 Slider 内部 padding 与手势竞技场影响，体验不稳定。
///
/// 本实现直接绘制轨道与拇指，手势自管（点击轨道即跳转、拖动跟手），
/// 轨道起点精确落在 [kPlayerLeftInset]、右缘留 20 与底栏对齐。
class PlayerSeekBar extends StatelessWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const PlayerSeekBar({
    super.key,
    required this.valueMs,
    required this.maxMs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  /// 进度条整体高度（含可点击热区）
  static const double barHeight = 40;

  /// 右缘间距（与底栏按钮行右缘对齐）
  static const double rightInset = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: barHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackLeft = kPlayerLeftInset;
          final trackWidth =
              (constraints.maxWidth - trackLeft - rightInset).clamp(0.0, double.infinity);
          final fraction =
              maxMs > 0 ? (valueMs / maxMs).clamp(0.0, 1.0) : 0.0;
          final thumbDx = trackLeft + trackWidth * fraction;
          final centerY = barHeight / 2;

          void handleAt(double dx) {
            if (trackWidth <= 0 || maxMs <= 0) return;
            final f = ((dx - trackLeft) / trackWidth).clamp(0.0, 1.0);
            onChanged(f * maxMs);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点击轨道：预览（onChanged）→ 松手即跳转（onChangeEnd，用点击位置计算）
            onTapDown: (d) => handleAt(d.localPosition.dx),
            onTapUp: (d) {
              if (trackWidth <= 0 || maxMs <= 0) return;
              final f = ((d.localPosition.dx - trackLeft) / trackWidth)
                  .clamp(0.0, 1.0);
              onChangeEnd(f * maxMs);
            },
            // 拖动：实时预览，松手跳转（与原有 onChanged/onChangeEnd 契约一致）
            onHorizontalDragStart: (d) => handleAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => handleAt(d.localPosition.dx),
            onHorizontalDragEnd: (_) => onChangeEnd(valueMs),
            onHorizontalDragCancel: () => onChangeEnd(valueMs),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 底轨（未播放部分）
                Positioned(
                  left: trackLeft,
                  right: rightInset,
                  top: centerY - 1.25,
                  height: 2.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(1.25),
                    ),
                  ),
                ),
                // 已播放部分（主题色）
                Positioned(
                  left: trackLeft,
                  top: centerY - 1.25,
                  width: (thumbDx - trackLeft).clamp(0.0, trackWidth),
                  height: 2.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(1.25),
                    ),
                  ),
                ),
                // 拇指
                Positioned(
                  left: thumbDx - 6,
                  top: centerY - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
