import 'package:flutter/material.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';

/// 底栏：全宽进度条 + 下一集 + 时间 + 超分辨率入口。
///
/// 左下角为「下一集」（无兄弟视频时置灰，设计上不提供上一集）；
/// 右下角为「超分辨率」胶囊（占位入口，待接入超分功能），
/// 距屏幕右缘留出间距，不紧贴边缘。
class PlayerBottomBar extends StatelessWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final bool hasNext;
  final VoidCallback onNext;
  final String timeText;
  final String superResolutionLabel;
  final VoidCallback onSuperResolutionTap;

  const PlayerBottomBar({
    super.key,
    required this.valueMs,
    required this.maxMs,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.hasNext,
    required this.onNext,
    required this.timeText,
    required this.superResolutionLabel,
    required this.onSuperResolutionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        // 横屏时挖孔在物理左/右侧，底部控制栏同样不消费左右 inset
        left: false,
        top: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerSeekBar(
              valueMs: valueMs,
              maxMs: maxMs,
              onChanged: onSeekChanged,
              onChangeEnd: onSeekEnd,
            ),
            Padding(
              // 右缘留 20 间距，胶囊不贴屏幕边缘
              padding: const EdgeInsets.fromLTRB(4, 0, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 32),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                    ),
                    tooltip: '下一集',
                    onPressed: hasNext ? onNext : null,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeText,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onSuperResolutionTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        superResolutionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
