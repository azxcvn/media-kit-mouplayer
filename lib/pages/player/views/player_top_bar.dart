import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 顶栏：返回 + 标题 + 自定义槽位（最多 5 个，空槽隐藏）+ 固定「更多」按钮。
///
/// 槽位内容由用户在「更多 → 编辑控制栏」中自由放置/排序；
/// 「更多」按钮不可删除、不占槽位，是唯一的编辑入口。
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
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                      IconButton(
                        icon: Icon(a.icon, color: Colors.white, size: 22),
                        tooltip: a.label,
                        onPressed: () => onActionTap(a),
                      ),
                  ],
                );
              },
            ),
            // 固定「更多」按钮（竖三点，更符合直觉），距右缘留间距
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: '更多',
                onPressed: onMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
