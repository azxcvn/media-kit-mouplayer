import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_chapter_bar.dart';
import 'package:moumou/pages/player/views/player_danmaku_buttons.dart';
import 'package:moumou/pages/player/views/player_pressable.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';

/// 竖屏播放页底栏（v3 布局）：
/// - **章节名 + 弹幕按钮行**：进度条上方——章节名靠左（点击呼出章节列表，
///   无章节时不占位），**弹幕开关/设置按钮靠右**（工作.md 弹幕第 5 点：
///   右下角、进度条上方，与章节名同一行；间距 6 与右侧簇按钮间距一致）；
/// - **进度条**（复用 [PlayerSeekBar]，轨道开端对齐 [kPlayerLeftInset]，
///   与返回/下一集同一 x）；
/// - **操作行**：下一集 + 时间文本（点击切换已播/总⇄已播/剩余）+
///   右侧按钮簇（从右到左，工作.md 第 18 点）：**选择屏幕 → 倍速 → 列表 →
///   超分辨率**（即左到右：超分辨率胶囊 → 列表图标 → 倍速图标 → 选择屏幕图标）。
///
/// 倍速/选择屏幕图标默认纯图标无背景；「按钮背景」设置开启后显示半透明
/// 圆角背景；列表按钮恒为纯图标无背景。底部渐变压暗（与横屏底栏一致）。
class PortraitPlayerBottomBar extends StatelessWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final bool hasNext;
  final VoidCallback onNext;
  final String timeText;
  final VoidCallback onTimeTap;
  final VoidCallback onSpeedTap;
  final bool showSpeedButtonBackground;
  final String superResolutionLabel;
  final VoidCallback onSuperResolutionTap;

  /// 「选择屏幕」：切回横屏（本页退出返回横屏播放页，最右侧按钮）
  final VoidCallback onScreenSwitchTap;

  /// 选择屏幕图标是否显示半透明圆角背景（与倍速按钮同设置）
  final bool showScreenSwitchBackground;

  /// 「列表」图标是否显示半透明圆角背景（工作.md 第 4 点：与倍速按钮同设置）
  final bool showListButtonBackground;

  /// 「列表」：底部弹出播放列表面板（倍速按钮左侧）
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

  /// 点击弹幕开关（显示 ⇄ 隐藏，工作.md 弹幕第 5 点：右下角、进度条上方）
  final VoidCallback onDanmakuToggle;

  /// 点击弹幕设置（弹幕开关右侧，与开关间距同右侧簇按钮间距 6）
  final VoidCallback onDanmakuSettingsTap;

  const PortraitPlayerBottomBar({
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
        // 竖屏下消费底部 inset（手势条/导航键），左右不消费
        left: false,
        top: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 左对齐：章节名称行（min 宽度）与进度条左缘对齐，不被居中
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节名 + 弹幕按钮行（进度条上方，工作.md 弹幕第 5 点）：
            // 章节名靠左（无章节时不占位，由 Spacer 顶位），弹幕开关/设置
            // 按钮靠右——与章节名同一行；间距 6 与下方操作行右侧簇一致。
            // 章节名用 Align+Expanded 顶宽（按钮贴右），点击区域仍只包住
            // 文字与箭头（Align 不参与命中，维持章节名行的原点击语义）。
            Row(
              children: [
                if (currentChapterName != null && onChapterTap != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PlayerChapterNameRow(
                        name: currentChapterName!,
                        onTap: onChapterTap!,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                Padding(
                  // 垂直内边距与章节名行（8/2）对齐，右缘同为 20
                  padding: const EdgeInsets.fromLTRB(0, 8, 20, 2),
                  child: PlayerDanmakuButtons(
                    danmakuOn: danmakuOn,
                    onToggle: onDanmakuToggle,
                    onSettings: onDanmakuSettingsTap,
                    iconSize: 20,
                    gap: 6,
                    buttonPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                  ),
                ),
              ],
            ),
            // ── 进度条：PlayerSeekBar 内部已按 kPlayerLeftInset 对齐轨道开端 ──
            PlayerSeekBar(
              valueMs: valueMs,
              maxMs: maxMs,
              onChanged: onSeekChanged,
              onChangeEnd: onSeekEnd,
              chapters: chapters,
              skipSegments: skipSegments,
            ),
            // ── 操作行：下一集 + 时间（点击切换）+ 右侧按钮簇 ──
            Padding(
              // 左缘与进度条开端对齐（kPlayerLeftInset），右缘留 20
              padding: const EdgeInsets.fromLTRB(kPlayerLeftInset, 0, 20, 10),
              child: Row(
                children: [
                  // 下一集：紧凑尺寸（默认 48dp 触摸目标在竖屏窄屏会溢出）；
                  // 视觉尺寸与原 IconButton（minimumSize 38×40）一致
                  PlayerPressable(
                    onTap: hasNext ? onNext : null,
                    child: Tooltip(
                      message: '下一集',
                      child: SizedBox(
                        width: 38,
                        height: 40,
                        child: Icon(
                          Icons.skip_next_rounded,
                          size: 26,
                          color: hasNext ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
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
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 右侧按钮簇（从右到左，工作.md 第 18 点）：
                  // 选择屏幕（最右）→ 倍速（图标）→ 列表（图标）→ 超分辨率（文本）
                  _PortraitBottomPill(
                    label: superResolutionLabel,
                    onTap: onSuperResolutionTap,
                  ),
                  const SizedBox(width: 6),
                  _PortraitBottomIconButton(
                    icon: Icons.playlist_play,
                    showBackground: showListButtonBackground,
                    tooltip: '播放列表',
                    onTap: onPlaylistTap,
                  ),
                  const SizedBox(width: 6),
                  _PortraitBottomIconButton(
                    icon: Icons.speed_rounded,
                    showBackground: showSpeedButtonBackground,
                    onTap: onSpeedTap,
                  ),
                  const SizedBox(width: 6),
                  _PortraitBottomIconButton(
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

/// 底栏右下角的固定功能胶囊（超分辨率，样式对齐横屏底栏），
/// 带按压缩放反馈（[PlayerPressable]）。
class _PortraitBottomPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PortraitBottomPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PlayerPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 底栏倍速/列表/选择屏幕图标按钮：默认纯图标无背景；[showBackground]
/// 为 true 时套半透明圆角背景（样式对齐横屏底栏倍速按钮）；
/// [tooltip] 非空时包裹 Tooltip。
class _PortraitBottomIconButton extends StatelessWidget {
  final IconData icon;
  final bool showBackground;
  final VoidCallback onTap;
  final String? tooltip;

  const _PortraitBottomIconButton({
    required this.icon,
    required this.showBackground,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 15, color: Colors.white);
    final Widget inner;
    if (!showBackground) {
      // 紧凑尺寸（v3 溢出修复：竖屏窄屏按钮行超宽）
      inner = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Icon(icon, size: 20, color: Colors.white),
      );
    } else {
      // 有背景时与顶栏控制图标同款：小圆形背景（28×28）+ 小图标
      inner = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(child: iconWidget),
      );
    }
    final child = tooltip == null
        ? inner
        : Tooltip(message: tooltip!, child: inner);
    return PlayerPressable(onTap: onTap, child: child);
  }
}
