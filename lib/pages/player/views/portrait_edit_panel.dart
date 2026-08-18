import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/pages/player/views/portrait_player_top_bar.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 「编辑控制栏」页内容（竖屏播放页「更多」底部面板的二级页）。
///
/// 与横屏播放页的编辑面板共用同一份 [PlayerControlsSettings] 数据：
/// - 「已启用」区：长按拖拽排序 + 文本「删除」；
/// - 「可添加」区：未启用动作，文本「添加」；
/// - 「重置控制栏」：清空全部槽位。
///
/// ⚠️ v3 用户反馈：竖屏窄屏最多 4 个槽位（[PortraitPlayerTopBar.maxPortraitSlots]），
/// 「可添加」以 4 为上限（与顶栏渲染一致）。
///
/// 拖拽高亮修复（工作.md 第 14 点）：默认 proxyDecorator 会把拖拽项包在
/// 带 elevation 的 Material 里，深色主题下产生白色高亮 —— 改用
/// `ColoredBox(onInverseSurface)`（PiliPlus 同款），彻底消除白底。
class PortraitEditControlPanel extends StatelessWidget {
  const PortraitEditControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: PlayerControlsSettings.instance,
      builder: (context, _) {
        final settings = PlayerControlsSettings.instance;
        final enabled = settings.topActions;
        final disabled = PlayerTopAction.values
            .where((a) => !enabled.contains(a))
            .toList();
        // 竖屏上限 4（v3 用户反馈），低于横屏的全局上限 5
        final portraitFull =
            enabled.length >= PortraitPlayerTopBar.maxPortraitSlots;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (enabled.isNotEmpty) ...[
              const PortraitPanelSectionLabel('已启用（长按拖拽排序）'),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: enabled.length,
                onReorderItem: (o, n) => settings.reorderTopAction(o, n),
                // 深色下长按高亮修复：ColoredBox 而非带 elevation 的 Material
                proxyDecorator: (child, index, animation) => ColoredBox(
                  color: scheme.onInverseSurface,
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final a = enabled[index];
                  return ListTile(
                    key: ValueKey(a.id),
                    leading: Icon(a.icon, color: Colors.white),
                    title: Text(
                      a.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: a.implemented
                        ? null
                        : const Text(
                            '功能即将上线',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                    trailing: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () => settings.removeTopAction(a),
                      child: const Text('删除'),
                    ),
                  );
                },
              ),
              const Divider(height: 1, color: Colors.white12),
            ],
            if (disabled.isNotEmpty) ...[
              const PortraitPanelSectionLabel('可添加'),
              for (final a in disabled)
                ListTile(
                  leading: Icon(a.icon, color: Colors.white),
                  title: Text(
                    a.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    !a.implemented
                        ? '功能即将上线'
                        : (portraitFull
                            ? '竖屏最多 4 个，需先移除一个'
                            : ''),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: portraitFull ? null : () => settings.addTopAction(a),
                    child: const Text('添加'),
                  ),
                ),
              const Divider(height: 1, color: Colors.white12),
            ],
            PortraitPanelActionTile(
              icon: Icons.restart_alt,
              label: '重置控制栏',
              subtitle: '清空全部槽位（仅保留「更多」按钮）',
              onTap: settings.resetTopActions,
            ),
          ],
        );
      },
    );
  }
}

/// 面板中的动作行：图标 + 名称 +（副标题）+ 箭头
class PortraitPanelActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const PortraitPanelActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}

/// 面板内的小节标题（已启用 / 可添加）
class PortraitPanelSectionLabel extends StatelessWidget {
  final String text;

  const PortraitPanelSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
