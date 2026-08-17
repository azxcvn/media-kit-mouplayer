import 'package:flutter/material.dart';

/// 全宽进度条：拖动实时预览目标时间，松手跳转。
/// 样式为默认细线，颜色跟随主题（播放页黑色背景下使用主题色 primary）。
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
    final scheme = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: scheme.primary,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.2),
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
