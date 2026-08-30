import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_pressable.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 竖屏播放页顶栏：两行布局。
///
/// - 第一行：返回 + 标题（弹性）；
/// - 第二行：自定义槽位（**最多 5 个**）+ 固定「更多」按钮，共 6 个按钮
///   **横向均匀分布**（与横屏一致支持 5 槽位，避免横竖切换丢槽位；
///   控制栏从标题行拆出、另起一行）。
///
/// 返回按钮左缘与底栏进度条开端/时间/下一集对齐（[kPlayerLeftInset]，
/// 工作.md 第 19 点人体工学）。
///
/// 控制按钮背景：与横屏顶栏一致，受「播放器设置 → 按钮背景」控制
/// （默认关闭 = 纯图标）。
///
/// ⚠️ SafeArea 不消费顶部 inset（v3 用户反馈：顶部 inset 把返回/控制行
/// 大幅往下顶）：播放页沉浸式全屏，控制行紧贴屏幕顶部。
/// ⚠️ 顶部渐变压暗由页面层统一提供（「信息行 + 本顶栏」整体一个连续
/// 渐变）：本组件不再自带渐变，避免两段渐变拼接的「阴影在时间电量下方」
/// 断层（用户反馈 v2）。
class PortraitPlayerTopBar extends StatelessWidget {
  /// 竖屏顶栏最多渲染的槽位数（与横屏一致，5 个）
  static const int maxPortraitSlots = 5;

  final String title;
  final VoidCallback onBack;
  final VoidCallback onMore;

  /// 点击槽位动作（与横屏 [PlayerTopBar.onActionTap] 同语义，
  /// 由播放页传入动作处理入口）
  final void Function(PlayerTopAction) onActionTap;

  const PortraitPlayerTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onMore,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBg = PlayerControlsSettings.instance.showButtonBackground;
    return SafeArea(
      left: false,
      right: false,
      bottom: false,
      // 不消费顶部 inset：见文件头注释（v3 用户反馈：顶部大间隔）
      top: false,
      child: Padding(
        // top 留出空间，远离状态栏/刘海；顶部信息行已单独占一行
        padding: const EdgeInsets.fromLTRB(kPlayerLeftInset, 4, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：返回 + 标题
            Row(
              children: [
                _PortraitTopIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '返回',
                  showBackground: showBg,
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // 第二行：槽位 + 更多（有槽位时横向均匀分布；无槽位时更多固定右侧）
            ListenableBuilder(
              listenable: PlayerControlsSettings.instance,
              builder: (context, _) {
                final actions = PlayerControlsSettings.instance.topActions;
                if (actions.isEmpty) {
                  // 无槽位：更多按钮固定右侧（不参与均分）
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _PortraitTopIconButton(
                        icon: Icons.more_vert,
                        tooltip: '更多',
                        showBackground: showBg,
                        onPressed: onMore,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (final a in actions.take(maxPortraitSlots))
                      Expanded(
                        child: Center(
                          child: _PortraitTopIconButton(
                            icon: a.icon,
                            tooltip: a.label,
                            showBackground: showBg,
                            onPressed: () => onActionTap(a),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Center(
                        child: _PortraitTopIconButton(
                          icon: Icons.more_vert,
                          tooltip: '更多',
                          showBackground: showBg,
                          onPressed: onMore,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏图标按钮：[showBackground] 为 true 时套半透明圆角背景
/// （与横屏顶栏 _TopIconButton 同款样式），false 时纯图标；
/// 带按压缩放反馈（[PlayerPressable]）。
class _PortraitTopIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool showBackground;
  final VoidCallback onPressed;

  const _PortraitTopIconButton({
    required this.icon,
    required this.tooltip,
    required this.showBackground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // 无背景：48dp 触摸目标（与原 IconButton 一致），纯图标
    if (!showBackground) {
      return PlayerPressable(
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
    }
    // 有背景：小圆形背景（28×28）+ 小图标，紧凑不占空间
    return PlayerPressable(
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
