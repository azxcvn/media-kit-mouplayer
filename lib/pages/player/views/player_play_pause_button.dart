import 'package:flutter/material.dart';

/// 播放/暂停图标：PiliPlus 风格的两态形变动画（AnimatedIcon.play_pause）。
///
/// 使用 AnimationController 在「播放 ⇄ 暂停」之间平滑形变（200ms），
/// 播放中显示暂停图标（progress 1），暂停时显示播放图标（progress 0）。
/// 纯展示组件（不处理点击），点击行为由外层包装的 GestureDetector 负责。
class PlayerPlayPauseButton extends StatefulWidget {
  final bool playing;
  final double iconSize;

  const PlayerPlayPauseButton({
    super.key,
    required this.playing,
    this.iconSize = 32,
  });

  @override
  State<PlayerPlayPauseButton> createState() => _PlayerPlayPauseButtonState();
}

class _PlayerPlayPauseButtonState extends State<PlayerPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.playing ? 1 : 0,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void didUpdateWidget(covariant PlayerPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      semanticLabel: widget.playing ? '暂停' : '播放',
      progress: _controller,
      icon: AnimatedIcons.play_pause,
      color: Colors.white,
      size: widget.iconSize,
    );
  }
}
