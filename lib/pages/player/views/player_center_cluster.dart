import 'package:flutter/material.dart';
import 'package:moumou/pages/player/views/player_play_pause_button.dart';

/// 中央控制簇：快退 - 播放/暂停 - 快进（对称三键）。
/// 快进/快退使用双三角图标（fast_rewind / fast_forward），贴住大播放键，
/// 拇指横屏自然覆盖。
class PlayerCenterCluster extends StatelessWidget {
  final int seekSeconds;
  final bool playing;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final VoidCallback onTogglePlay;

  const PlayerCenterCluster({
    super.key,
    required this.seekSeconds,
    required this.playing,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(
            Icons.fast_rewind_rounded,
            color: Colors.white,
            size: 40,
          ),
          tooltip: '快退 $seekSeconds 秒',
          onPressed: onSeekBackward,
        ),
        const SizedBox(width: 24),
        _BigPlayPauseButton(playing: playing, onPressed: onTogglePlay),
        const SizedBox(width: 24),
        IconButton(
          icon: const Icon(
            Icons.fast_forward_rounded,
            color: Colors.white,
            size: 40,
          ),
          tooltip: '快进 $seekSeconds 秒',
          onPressed: onSeekForward,
        ),
      ],
    );
  }
}

/// 中央大播放/暂停键：按压缩放反馈 + 图标切换动画
class _BigPlayPauseButton extends StatefulWidget {
  final bool playing;
  final VoidCallback onPressed;

  const _BigPlayPauseButton({required this.playing, required this.onPressed});

  @override
  State<_BigPlayPauseButton> createState() => _BigPlayPauseButtonState();
}

class _BigPlayPauseButtonState extends State<_BigPlayPauseButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.92),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: PlayerPlayPauseButton(
              playing: widget.playing,
              iconSize: 44,
            ),
          ),
        ),
      ),
    );
  }
}
