/// 弹幕服务器设置子页（工作.md 第 6/7 点）：
/// - 启用/停用已添加的弹幕服务器（弹弹Play 默认服务器不可删除，只能开关）；
/// - 右下角加号添加自建服务器（名称 + 地址），已添加服务器可自由删除/启停；
/// - 「切集自动匹配弹幕」开关（开发阶段**解除**弹弹Play 启用时禁用的写死
///   限制，待联调通过、收尾阶段再恢复，见 [DanmakuServerSettings]）。
///
/// 启用的服务器同时用于网络弹幕搜索（结果合并展示）与自动匹配。
library;

import 'package:flutter/material.dart';
import 'package:moumou/models/danmaku_server.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/widgets/settings_ui.dart';

class DanmakuServerPage extends StatelessWidget {
  const DanmakuServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = DanmakuServerSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕服务器')),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加服务器',
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Text(
                '启用的服务器将同时用于弹幕搜索，搜索结果会合并展示',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SettingsCard(
                child: SettingsSwitchTile(
                  icon: Icons.autorenew,
                  title: '切集自动匹配弹幕',
                  subtitle: const Text('切集时自动匹配并加载对应集弹幕'),
                  value: settings.autoMatchEnabled,
                  onChanged: (v) => settings.setAutoMatchEnabled(v),
                ),
              ),
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '服务器'),
              for (final server in settings.servers) ...[
                _DanmakuServerCard(
                  server: server,
                  onToggle: (enabled) =>
                      settings.setServerEnabled(server.id, enabled),
                  onDelete: () => settings.removeServer(server.id),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await showAppDialog<void>(
      context: context,
      builder: (context) => const _AddServerDialog(),
    );
  }
}

/// 单个服务器卡片：开关 + 名称/地址 + 删除（默认服务器不显示删除）。
class _DanmakuServerCard extends StatelessWidget {
  final DanmakuServer server;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _DanmakuServerCard({
    required this.server,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Switch(value: server.isEnabled, onChanged: onToggle),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.url,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (server.isDefault) ...[
                    const SizedBox(height: 2),
                    Text(
                      '内置服务器，不可删除',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ],
              ),
            ),
            if (!server.isDefault)
              IconButton(
                tooltip: '删除',
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

/// 添加弹幕服务器弹窗（名称 + 地址）。
class _AddServerDialog extends StatefulWidget {
  const _AddServerDialog();

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onChanged);
    _urlController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.removeListener(_onChanged);
    _urlController.removeListener(_onChanged);
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _urlController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    await DanmakuServerSettings.instance.addServer(
      _nameController.text,
      _urlController.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加弹幕服务器'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '服务器名称',
              hintText: '例：我的服务器',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://example.com',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
