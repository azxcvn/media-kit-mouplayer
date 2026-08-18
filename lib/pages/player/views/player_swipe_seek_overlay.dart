import 'package:flutter/material.dart';
import 'package:moumou/utils/formatters.dart';

/// 水平滑动 seek 预览浮层（居中，kt 项目 `SwipeSeekOverlay` 的 Flutter 版）：
/// 大号目标时间 + 偏移量（"+0:10" 蓝色 / "-0:10" 橙色）。
class PlayerSwipeSeekOverlay extends StatelessWidget {
  final Duration target;

  /// 带符号偏移（正 = 快进）
  final Duration delta;

  /// 是否显示（滑动中显示，松手隐藏）
  final bool visible;

  const PlayerSwipeSeekOverlay({
    super.key,
    required this.target,
    required this.delta,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatDuration(target.inMilliseconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _deltaText(delta),
                style: TextStyle(
                  color: delta >= Duration.zero
                      ? const Color(0xFF4FC3F7)
                      : const Color(0xFFFF8A65),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 偏移文本：正数 "+0:10"，负数 "-0:10"（分:秒，分钟不补零）
  static String _deltaText(Duration delta) {
    final sign = delta >= Duration.zero ? '+' : '-';
    final total = delta.inSeconds.abs();
    final m = total ~/ 60;
    final s = total % 60;
    return '$sign$m:${s.toString().padLeft(2, '0')}';
  }
}
