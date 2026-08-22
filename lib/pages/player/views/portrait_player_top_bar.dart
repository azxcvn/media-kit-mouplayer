import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 竖屏播放页顶栏：返回 + 标题（弹性）+ 自定义槽位（**最多 4 个**）+ 固定「更多」。
///
/// 布局对应横屏 [PlayerTopBar] 的简化版（对齐 src PortraitTopBar：
/// 顶部渐变压暗、top padding 加大避让状态栏/刘海；去掉电量/时间，
/// 保留自定义槽位渲染 —— 用户添加的槽位动作在「更多」按钮前显示，空列表
/// 不占位（t1 第 4 项修复：竖屏顶栏此前看不到已添加槽位按钮）。
///
/// ⚠️ v3 用户反馈：竖屏窄屏最多渲染 **4 个**槽位（第 5 个放不下会溢出），
/// 多余的仍在「更多 → 已启用动作」里可触发。
///
/// 返回按钮左缘与底栏进度条开端/时间/下一集对齐（[kPlayerLeftInset]，
/// 工作.md 第 19 点人体工学）。
///
/// 控制按钮背景：与横屏顶栏一致，受「播放器设置 → 按钮背景」控制
/// （默认关闭 = 纯图标）。
///
/// ⚠️ 顶部渐变压暗由页面层统一提供（「信息行 + 本顶栏」整体一个连续
/// 渐变）：本组件不再自带渐变，避免两段渐变拼接的「阴影在时间电量下方」
/// 断层（用户反馈 v2）。
///
/// ⚠️ SafeArea 不再消费顶部 inset（用户反馈 v3：竖屏下顶部 inset 把
/// 返回/控制行大幅往下顶，与上方时间/电量行之间出现超大间隔）：
/// 播放页为沉浸式全屏，视频本身延伸到状态栏/挖孔区域，控制行跟随
/// 信息行紧贴屏幕顶部即可。
class PortraitPlayerTopBar extends StatelessWidget {
  /// 竖屏顶栏最多渲染的槽位数（v3 用户反馈：5 个会超出屏宽）
  static const int maxPortraitSlots = 4;

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
        // top 留出更大空间，远离状态栏/刘海（PortraitTopBar 同款思路）；
        // 顶部信息行已单独占一行，这里 top 减小避免顶栏被顶得过低
        // （用户反馈：竖屏下状态栏把控制组件大幅往下顶）
        padding: const EdgeInsets.fromLTRB(kPlayerLeftInset, 4, 4, 4),
          child: Row(
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
              // 槽位区：与横屏 PlayerTopBar 一致，随设置变化自动重建；
              // 空列表时不占任何空间；竖屏最多渲染 4 个（v3 用户反馈）
              ListenableBuilder(
                listenable: PlayerControlsSettings.instance,
                builder: (context, _) {
                  final actions =
                      PlayerControlsSettings.instance.topActions;
                  if (actions.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final a in actions.take(maxPortraitSlots))
                        _PortraitTopIconButton(
                          icon: a.icon,
                          tooltip: a.label,
                          showBackground: showBg,
                          onPressed: () => onActionTap(a),
                        ),
                    ],
                  );
                },
              ),
              // 固定「更多」按钮（竖三点），距右缘留间距
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PortraitTopIconButton(
                  icon: Icons.more_vert,
                  tooltip: '更多',
                  showBackground: showBg,
                  onPressed: onMore,
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// 顶栏图标按钮：[showBackground] 为 true 时套半透明圆角背景
/// （与横屏顶栏 _TopIconButton 同款样式），false 时纯图标。
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
    // 无背景：默认 IconButton（48dp 触摸目标，纯图标）
    if (!showBackground) {
      return IconButton(
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    // 有背景：小圆形背景（28×28）+ 小图标，紧凑不占空间
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 16),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
