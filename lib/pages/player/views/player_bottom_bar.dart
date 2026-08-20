import 'package:flutter/material.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';

/// 底栏：全宽进度条 + 下一集 + 时间 + 右下角按钮组（超分辨率/列表/倍速/选择屏幕）。
///
/// 布局（工作.md 第 18/19 点 + v3 用户反馈）：
/// - 左下角「下一集」（无兄弟视频时置灰）+ 其右侧为**时间文本**（点击在
///   「已播/总时长」⇄「已播/剩余时长」间切换，onTimeTap），三者左缘与
///   进度条开端/返回箭头对齐到同一 x（[kPlayerLeftInset]）；
/// - 右下角按钮从右到左：**选择屏幕**（最右）→ **倍速**（图标）→ **列表**（图标）
///   → **超分辨率**（文本胶囊，最左）。
///
/// 倍速/选择屏幕图标默认**纯图标无背景**；设置「播放器设置 → 按钮背景」开启后
/// 显示半透明圆角背景（与顶栏控制图标一致）；列表按钮恒为纯图标无背景。
class PlayerBottomBar extends StatelessWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final bool hasNext;
  final VoidCallback onNext;
  final String timeText;

  /// 点击时间文本：切换「已播/总时长」⇄「已播/剩余时长」（工作.md 第 20 点）
  final VoidCallback onTimeTap;
  final VoidCallback onSpeedTap;
  final bool showSpeedButtonBackground;
  final String superResolutionLabel;
  final VoidCallback onSuperResolutionTap;

  /// 「选择屏幕」：切换到竖屏播放页（最右侧按钮）
  final VoidCallback onScreenSwitchTap;

  /// 选择屏幕图标是否显示半透明圆角背景（与倍速按钮同设置）
  final bool showScreenSwitchBackground;

  /// 「列表」图标是否显示半透明圆角背景（工作.md 第 4 点：与倍速按钮同设置）
  final bool showListButtonBackground;

  /// 「列表」：打开播放列表面板（倍速按钮左侧）
  final VoidCallback onPlaylistTap;

  const PlayerBottomBar({
    super.key,
    required this.valueMs,
    required this.maxMs,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.hasNext,
    required this.onNext,
    required this.timeText,
    required this.onTimeTap,
    required this.onSpeedTap,
    required this.showSpeedButtonBackground,
    required this.superResolutionLabel,
    required this.onSuperResolutionTap,
    required this.onScreenSwitchTap,
    required this.showScreenSwitchBackground,
    required this.onPlaylistTap,
    this.showListButtonBackground = false,
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
              // 左缘与进度条开端对齐（kPlayerLeftInset），右缘留 20
              padding: const EdgeInsets.fromLTRB(kPlayerLeftInset, 0, 20, 8),
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
                  // 时间文本：下一集右侧（v3 用户反馈改回此款式），
                  // 点击切换「已播/总时长」⇄「已播/剩余时长」。
                  // ⚠️ 布局要点：Expanded 是**唯一**弹性元素——时间文本占满
                  // 「下一集」与按钮簇之间的剩余空间（左对齐、过长省略），
                  // 右侧按钮簇保持贴右缘（若用 Flexible+Spacer 两个弹性元素
                  // 会平分自由空间，把按钮推向中间，v3 回归根因）。
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTimeTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Text(
                          timeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 右侧按钮簇（从右到左，工作.md 第 18 点）：
                  // 选择屏幕（最右）→ 倍速（图标）→ 列表（图标）→ 超分辨率（胶囊，最左）
                  _BottomPill(
                    label: superResolutionLabel,
                    onTap: onSuperResolutionTap,
                  ),
                  const SizedBox(width: 8),
                  _BottomIconButton(
                    icon: Icons.playlist_play,
                    showBackground: showListButtonBackground,
                    tooltip: '播放列表',
                    onTap: onPlaylistTap,
                  ),
                  const SizedBox(width: 8),
                  _BottomIconButton(
                    icon: Icons.speed_rounded,
                    showBackground: showSpeedButtonBackground,
                    onTap: onSpeedTap,
                  ),
                  const SizedBox(width: 8),
                  _BottomIconButton(
                    icon: Icons.screen_rotation,
                    showBackground: showScreenSwitchBackground,
                    tooltip: '选择屏幕',
                    onTap: onScreenSwitchTap,
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

/// 底栏倍速/选择屏幕图标按钮：默认纯图标无背景；[showBackground] 为 true 时
/// 套半透明圆角背景（与顶栏控制图标一致）。
class _BottomIconButton extends StatelessWidget {
  final IconData icon;
  final bool showBackground;
  final VoidCallback onTap;
  final String? tooltip;

  const _BottomIconButton({
    required this.icon,
    required this.showBackground,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 16, color: Colors.white);
    final Widget inner;
    if (!showBackground) {
      inner = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Icon(icon, size: 22, color: Colors.white),
      );
    } else {
      // 有背景时与顶栏控制图标同款：小圆形背景（28×28）+ 小图标
      inner = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(child: iconWidget),
      );
    }
    final child = tooltip == null ? inner : Tooltip(message: tooltip!, child: inner);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
