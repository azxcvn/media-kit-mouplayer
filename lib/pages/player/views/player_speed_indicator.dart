import 'package:flutter/material.dart';
import 'package:moumou/utils/formatters.dart';

/// 长按倍速指示器（顶部居中，kt 项目 `LongPressSpeedOverlay` 的 Flutter 版）：
///
/// - 速度胶囊：一直长按一直显示「正在 X.Xx 倍速播放」；
/// - 首次提示：尚未完成过「长按 + 左右滑动」时，在速度胶囊下方提示
///   「左右滑动可临时调节长按倍数」；
/// - 倍速条：长按且左右拖动调速后出现（位于指示器下方），显示全部
///   动态档位，当前档位高亮；停止操作 3 秒后自动隐藏（由页面计时控制）。
///
/// [visible] 由页面控制（长按中且设置开启指示器）；整体淡入淡出。
class PlayerSpeedIndicator extends StatelessWidget {
  final double speed;

  /// 整体显隐（长按中 && 设置开启）
  final bool visible;

  /// 是否已发生左右滑动调速
  final bool dynamicActive;

  /// 倍速条显隐（调速后 3 秒内）
  final bool showBar;

  /// 是否显示首次使用提示（尚未完成过长按+滑动）
  final bool showHint;

  /// 动态倍速档位（1.5 – 4.0 间隔 0.5）
  final List<double> presets;

  const PlayerSpeedIndicator({
    super.key,
    required this.speed,
    required this.visible,
    required this.dynamicActive,
    required this.showBar,
    required this.showHint,
    required this.presets,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 速度胶囊（常驻）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      '正在 ${formatSpeed(speed)} 倍速播放',
                      key: ValueKey(speed.toStringAsFixed(2)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 首次使用提示（尚未掌握动态调速时显示）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: showHint && !dynamicActive
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '左右滑动可临时调节长按倍数',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // 倍速条（动态调速后出现，位于指示器下方）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: dynamicActive && showBar
                  ? Padding(
                      key: const ValueKey('speed-bar'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final p in presets) ...[
                              if (p != presets.first) const SizedBox(width: 6),
                              _PresetText(
                                label: _presetLabel(p),
                                selected: (speed - p).abs() < 0.01,
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  static String _presetLabel(double p) =>
      p == p.roundToDouble() ? '${p.toInt()}x' : '${p.toStringAsFixed(1)}x';
}

class _PresetText extends StatelessWidget {
  final String label;
  final bool selected;

  const _PresetText({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 150),
      style: TextStyle(
        color: selected
            ? const Color(0xFF4FC3F7)
            : Colors.white.withValues(alpha: 0.6),
        fontSize: selected ? 14 : 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      child: Text(label),
    );
  }
}
