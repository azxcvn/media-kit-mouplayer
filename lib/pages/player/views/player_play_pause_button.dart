import 'package:flutter/material.dart';

/// 播放/暂停图标：切换时缩放 + 淡入过渡（AnimatedSwitcher）。
///
/// 纯展示组件（不处理点击），点击行为由外层包装的 GestureDetector 负责，
/// 便于外层叠加按压缩放反馈。
class PlayerPlayPauseButton extends StatelessWidget {
  final bool playing;
  final double iconSize;

  const PlayerPlayPauseButton({
    super.key,
    required this.playing,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(playing),
        size: iconSize,
        color: Colors.white,
      ),
    );
  }
}
