import 'package:flutter/material.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';

/// 底栏：全宽进度条 + 下一集 + 时间 + 倍速（图标）+ 超分辨率。
///
/// 左下角为「下一集」（无兄弟视频时置灰，设计上不提供上一集）；
/// 右下角固定两个按钮：**倍速**（左侧，图标，不使用文本）→ **超分辨率**（右侧文本胶囊，
/// 距屏幕右缘留间距）。倍速按钮固定在底栏、不再出现在顶栏控制栏（不支持增加与删除），
/// 点击分别弹出与超分辨率一致的右侧滑入面板。
///
/// 倍速图标默认**纯图标无背景**；设置「播放器设置 → 按钮背景」开启后
/// 显示半透明圆角背景（与顶栏控制图标一致）。
class PlayerBottomBar extends StatelessWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final bool hasNext;
  final VoidCallback onNext;
  final String timeText;
  final VoidCallback onSpeedTap;
  final bool showSpeedButtonBackground;
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
    required this.onSpeedTap,
    required this.showSpeedButtonBackground,
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
                  // 倍速（图标，默认无背景）→ 超分辨率（文本），两按钮同高
                  _BottomIconButton(
                    icon: Icons.speed_rounded,
                    showBackground: showSpeedButtonBackground,
                    onTap: onSpeedTap,
                  ),
                  const SizedBox(width: 8),
                  _BottomPill(
                    label: superResolutionLabel,
                    onTap: onSuperResolutionTap,
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

/// 底栏右下角的固定功能胶囊（倍速 / 超分辨率共用样式）
class _BottomPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BottomPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 底栏倍速图标按钮：默认纯图标无背景；[showBackground] 为 true 时
/// 套半透明圆角背景（与顶栏控制图标一致），点击弹倍速面板。
class _BottomIconButton extends StatelessWidget {
  final IconData icon;
  final bool showBackground;
  final VoidCallback onTap;

  const _BottomIconButton({
    required this.icon,
    required this.showBackground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 16, color: Colors.white);
    if (!showBackground) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      );
    }
    // 有背景时与顶栏控制图标同款：小圆形背景（28×28）+ 小图标
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(child: iconWidget),
      ),
    );
  }
}
