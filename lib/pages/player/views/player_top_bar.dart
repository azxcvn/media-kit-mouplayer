import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 顶栏：返回 + 标题 + 自定义槽位（最多 5 个，空槽隐藏）+ 固定「更多」按钮。
///
/// 槽位内容由用户在「更多 → 编辑控制栏」中自由放置/排序；
/// 「更多」按钮不可删除、不占槽位，是唯一的编辑入口。
///
/// 控制按钮背景：设置「播放器设置 → 按钮背景」开启后，返回/槽位/更多
/// 图标显示半透明圆角背景（与底栏倍速图标一致）；默认关闭 = 纯图标。
class PlayerTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMore;
  final void Function(PlayerTopAction) onActionTap;

  const PlayerTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onMore,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    // 顶栏已随控制设置自动重建（槽位变化/背景开关共用同一监听）
    final showBg = PlayerControlsSettings.instance.showButtonBackground;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        // 横屏时挖孔在物理左/右侧，控制层不应消费左右 inset（见 AppFrame 约定）
        left: false,
        bottom: false,
        right: false,
        // 人体工学（工作.md 第 19 点）：返回按钮整体右移，与底栏进度条
        // 开端/下一集/时间文本对齐到同一 x（kPlayerLeftInset）
        child: Padding(
          padding: const EdgeInsets.only(left: kPlayerLeftInset),
          child: Row(
            children: [
              _TopIconButton(
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
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 槽位区：随设置变化自动重建；空列表时不占任何空间
            ListenableBuilder(
              listenable: PlayerControlsSettings.instance,
              builder: (context, _) {
                final actions = PlayerControlsSettings.instance.topActions;
                if (actions.isEmpty) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in actions)
                      _TopIconButton(
                        icon: a.icon,
                        tooltip: a.label,
                        showBackground: showBg,
                        onPressed: () => onActionTap(a),
                      ),
                  ],
                );
              },
            ),
            // 固定「更多」按钮（竖三点，更符合直觉），距右缘留间距
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _TopIconButton(
                icon: Icons.more_vert,
                tooltip: '更多',
                showBackground: showBg,
                onPressed: onMore,
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶栏图标按钮：[showBackground] 为 true 时套半透明圆角背景
/// （样式与底栏倍速图标胶囊一致），false 时纯图标。
class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool showBackground;
  final VoidCallback onPressed;

  const _TopIconButton({
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
