import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_chapter_bar.dart';
import 'package:moumou/pages/player/views/player_danmaku_buttons.dart';
import 'package:moumou/pages/player/views/player_pressable.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';

/// 底栏：全宽进度条 + 下一集 + 时间 + 弹幕开关/设置 + 右下角按钮组
/// （超分辨率/列表/倍速/选择屏幕）。
///
/// 布局（工作.md 第 18/19 点 + v3 用户反馈 + 弹幕第 5 点）：
/// - 左下角「下一集」（无兄弟视频时置灰）+ 其右侧为**时间文本**（点击在
///   「已播/总时长」⇄「已播/剩余时长」间切换，onTimeTap），三者左缘与
///   进度条开端/返回箭头对齐到同一 x（[kPlayerLeftInset]）；
/// - 时间文本右侧为**弹幕开关 + 弹幕设置**按钮（顺序固定，间距 8 与
///   右侧簇内按钮一致）；
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

  /// 章节标记数据（进度条节点圆点 + 跳过片段色段；开关关闭时传空）
  final List<ChapterInfo> chapters;
  final List<SkipSegment> skipSegments;

  /// 当前章节名称（无章节/开关关闭时为 null，不显示章节名行）
  final String? currentChapterName;

  /// 点击章节名称：呼出章节列表面板
  final VoidCallback? onChapterTap;

  /// 弹幕开关状态（开 = 带对勾主题色图标，关 = 斜杠图标）
  final bool danmakuOn;

  /// 点击弹幕开关（显示 ⇄ 隐藏，工作.md 弹幕第 5 点：位于时间文本右侧）
  final VoidCallback onDanmakuToggle;

  /// 点击弹幕设置（弹幕开关右侧，与开关间距同右侧簇按钮间距 8）
  final VoidCallback onDanmakuSettingsTap;

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
    this.chapters = const [],
    this.skipSegments = const [],
    this.currentChapterName,
    this.onChapterTap,
    required this.danmakuOn,
    required this.onDanmakuToggle,
    required this.onDanmakuSettingsTap,
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
          // 左对齐：章节名称行（min 宽度）与进度条左缘对齐，不被居中
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节名称行：进度条上方（工作.md 章节功能第 2 点），
            // 点击呼出章节列表；无章节时不占位。
            // bottom 10：进度条下移（height 24）后同步下移 8px，
            // 保持与轨道的间距不变（竖屏底栏用组件默认 padding）；
            // left 28：与进度条轨道起点（trackLeftInset）对齐
            if (currentChapterName != null && onChapterTap != null)
              PlayerChapterNameRow(
                name: currentChapterName!,
                onTap: onChapterTap!,
                padding: const EdgeInsets.fromLTRB(28, 8, 20, 10),
              ),
            // 进度条贴近下方控制行（用户反馈：间距过大）：
            // - height 24（默认 40）：轨道下移 8px，离控制行约 10px；
            // - trackLeftInset 28：轨道左端与「下一集」按钮图标左缘对齐
            //   （原 20 会比按钮多伸出 8px）
            PlayerSeekBar(
              valueMs: valueMs,
              maxMs: maxMs,
              onChanged: onSeekChanged,
              onChangeEnd: onSeekEnd,
              chapters: chapters,
              skipSegments: skipSegments,
              height: 24,
              trackLeftInset: 28,
            ),
            Padding(
              // 左缘与进度条开端对齐（kPlayerLeftInset），右缘留 20
              padding: const EdgeInsets.fromLTRB(kPlayerLeftInset, 0, 20, 8),
              child: Row(
                children: [
                  // 下一集（无兄弟视频时置灰）；48dp 触摸目标与原 IconButton 一致
                  PlayerPressable(
                    onTap: hasNext ? onNext : null,
                    child: Tooltip(
                      message: '下一集',
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.skip_next_rounded,
                          size: 32,
                          color: hasNext ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 时间文本：下一集右侧（v3 用户反馈改回此款式），
                  // 点击切换「已播/总时长」⇄「已播/剩余时长」。
                  // ⚠️ 布局要点：外层 Expanded 是**唯一**弹性元素——时间文本
                  // 与弹幕按钮组成子行占满「下一集」与右侧按钮簇之间的剩余
                  // 空间（时间文本 Flexible 左对齐、过长省略，弹幕按钮紧随
                  // 其右），右侧按钮簇保持贴右缘（若用 Flexible+Spacer 两个
                  // 弹性元素会平分自由空间，把按钮推向中间，v3 回归根因）。
                  // 弹幕开关/设置按钮在时间文本右侧（工作.md 弹幕第 5 点），
                  // 间距 8 与右侧播放列表/倍速按钮间距一致。
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
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
                        // ⚠️ FittedBox(scaleDown) 兜底：极窄窗口（分屏/自由
                        // 窗口把横屏页压到 ~390dp）下 Expanded 可能只剩几十
                        // px，固定尺寸按钮会 RenderFlex 溢出；常规宽度下
                        // 原尺寸渲染不受影响
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: PlayerDanmakuButtons(
                              danmakuOn: danmakuOn,
                              onToggle: onDanmakuToggle,
                              onSettings: onDanmakuSettingsTap,
                              iconSize: 22,
                              gap: 8,
                              buttonPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                      ],
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

/// 底栏右下角的固定功能胶囊（倍速 / 超分辨率共用样式），
/// 带按压缩放反馈（[PlayerPressable]）。
class _BottomPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BottomPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PlayerPressable(
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
    return PlayerPressable(onTap: onTap, child: child);
  }
}
