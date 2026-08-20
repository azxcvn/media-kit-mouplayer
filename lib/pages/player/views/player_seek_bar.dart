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
///
/// 触摸反馈（工作.md 第 1 点）：拇指被**触摸或拖动**时，在外面套一个
/// 比拇指大一圈的同心圆（低透明度），让用户感知已命中进度条
/// （轻微放大 + 外圈扩散效果）。
class PlayerSeekBar extends StatefulWidget {
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
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  /// 是否正处于「触摸 / 拖动」状态：为 true 时拇指外圈放大显示
  bool _interacting = false;

  void _setInteracting(bool v) {
    if (_interacting == v) return;
    setState(() => _interacting = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueMs = widget.valueMs;
    final maxMs = widget.maxMs;
    return SizedBox(
      height: PlayerSeekBar.barHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackLeft = kPlayerLeftInset;
          final trackWidth = (constraints.maxWidth -
                  trackLeft -
                  PlayerSeekBar.rightInset)
              .clamp(0.0, double.infinity);
          final fraction =
              maxMs > 0 ? (valueMs / maxMs).clamp(0.0, 1.0) : 0.0;
          final thumbDx = trackLeft + trackWidth * fraction;
          final centerY = PlayerSeekBar.barHeight / 2;

          void handleAt(double dx) {
            if (trackWidth <= 0 || maxMs <= 0) return;
            final f = ((dx - trackLeft) / trackWidth).clamp(0.0, 1.0);
            widget.onChanged(f * maxMs);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点击轨道：预览（onChanged）→ 松手即跳转（onChangeEnd，用点击位置计算）
            onTapDown: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onTapUp: (d) {
              _setInteracting(false);
              if (trackWidth <= 0 || maxMs <= 0) return;
              final f = ((d.localPosition.dx - trackLeft) / trackWidth)
                  .clamp(0.0, 1.0);
              widget.onChangeEnd(f * maxMs);
            },
            onTapCancel: () => _setInteracting(false),
            // 拖动：实时预览，松手跳转（与原有 onChanged/onChangeEnd 契约一致）
            onHorizontalDragStart: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onHorizontalDragEnd: (_) {
              _setInteracting(false);
              widget.onChangeEnd(valueMs);
            },
            onHorizontalDragCancel: () {
              _setInteracting(false);
              widget.onChangeEnd(valueMs);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 底轨（未播放部分）
                Positioned(
                  left: trackLeft,
                  right: PlayerSeekBar.rightInset,
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
                // 触摸/拖动反馈外圈：比拇指大一圈、低透明度，放大 + 淡入
                // （工作.md 第 1 点：被触摸时在小圆点外面套一个更大的圆形）
                Positioned(
                  left: thumbDx - 16,
                  top: centerY - 16,
                  child: IgnorePointer(
                    child: AnimatedScale(
                      scale: _interacting ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _interacting ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
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
