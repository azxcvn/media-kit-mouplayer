import 'package:flutter/material.dart';

/// 全宽细进度条：拖动实时预览目标时间，松手跳转。
/// 样式保持原有「白色细线 + 圆点拇指」，拖动时拇指放大由 Slider 内部处理。
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

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
        thumbColor: Colors.white,
        overlayColor: Colors.white.withValues(alpha: 0.2),
      ),
      child: Slider(
        min: 0,
        max: maxMs,
        value: valueMs.clamp(0.0, maxMs),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
