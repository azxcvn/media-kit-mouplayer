import 'package:flutter/material.dart';
import 'package:moumou/models/bilibili_user.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 哔哩哔哩账号信息页（工作.md 阶段一补充）：
/// 展示头像 / 昵称 / 等级 / 经验值 / 硬币 / 会员状态，并提供退出登录。
///
/// 数据来自 [BiliAccount.user]（nav 接口的 level_info / vip_label / money 等）。
class BiliUserPage extends StatelessWidget {
  const BiliUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('哔哩哔哩账号')),
      body: ListenableBuilder(
        listenable: BiliAccount.instance,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final user = BiliAccount.instance.user;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _HeaderCard(user: user),
              const SizedBox(height: 20),
              const SettingsGroupTitle(title: '等级'),
              SettingsCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.levelLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _expLabel(user),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _expProgress(user),
                        minHeight: 6,
                        backgroundColor: scheme.secondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SettingsGroupTitle(title: '资产'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.monetization_on_outlined,
                  title: '硬币',
                  subtitle: const Text('用于投币等操作'),
                  trailing: Text(
                    user.money.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('退出登录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _expProgress(BiliUser user) {
    if (user.nextExp <= 0) return 0;
    return (user.currentExp / user.nextExp).clamp(0.0, 1.0);
  }

  String _expLabel(BiliUser user) {
    if (user.level >= 6) return '已满级';
    return '经验值 ${user.currentExp} / ${user.nextExp}';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出哔哩哔哩账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BiliAccount.instance.logout();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// 头部卡片：头像 + 昵称 + 等级徽章 + 会员状态。
class _HeaderCard extends StatelessWidget {
  final BiliUser user;
  const _HeaderCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primaryContainer,
            foregroundImage: user.face.isEmpty ? null : NetworkImage(user.face),
            onForegroundImageError: user.face.isEmpty ? null : (_, _) {},
            child: user.face.isEmpty
                ? Icon(Icons.account_circle, color: scheme.onPrimaryContainer, size: 48)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nickname,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Badge(text: user.levelLabel, color: scheme.primary),
                    const SizedBox(width: 8),
                    _Badge(
                      text: user.vipLabel,
                      color: user.vipType > 0
                          ? const Color(0xFFFB7299)
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆角小徽章（等级 / 会员状态）。
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
