import 'package:flutter/material.dart';
import 'package:moumou/models/network_connection.dart';
import 'package:moumou/pages/network/account_edit_page.dart';
import 'package:moumou/pages/network/network_browser_page.dart';
import 'package:moumou/services/network/network_connection_settings.dart';
import 'package:moumou/widgets/speed_dial_fab.dart';

/// 网络存储账户列表：新增 / 编辑 / 删除 WebDAV、SMB、FTP 账户。
///
/// 点击账户卡片进入在线浏览（复用 FolderCard / VideoCard 的文件夹/视频列表）。
class NetworkStoragePage extends StatelessWidget {
  const NetworkStoragePage({super.key});

  Future<void> _openEdit(BuildContext context, {NetworkConnection? connection}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountEditPage(connection: connection),
      ),
    );
  }

  Future<void> _openBrowser(BuildContext context, NetworkConnection connection) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NetworkBrowserPage(connection: connection),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, NetworkConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${connection.name}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await NetworkConnectionSettings.instance.remove(connection.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络存储')),
      // 与主页速拨按钮一致：略高于悬浮胶囊导航栏的高度
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: kFabLiftAboveNav),
        child: FloatingActionButton(
          heroTag: 'network_add',
          tooltip: '添加账户',
          onPressed: () => _openEdit(context),
          child: const Icon(Icons.add),
        ),
      ),
      body: ListenableBuilder(
        listenable: NetworkConnectionSettings.instance,
        builder: (context, _) {
          final connections = NetworkConnectionSettings.instance.connections;
          if (connections.isEmpty) {
            return _emptyState(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: connections.length,
            itemBuilder: (context, index) {
              final connection = connections[index];
              return _AccountCard(
                connection: connection,
                onTap: () => _openBrowser(context, connection),
                onEdit: () => _openEdit(context, connection: connection),
                onDelete: () => _confirmDelete(context, connection),
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 80, color: scheme.outline),
          const SizedBox(height: 16),
          const Text('还没有网络存储账户'),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 添加 WebDAV / SMB / FTP 账户',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final NetworkConnection connection;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.connection,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _protocolIcon(connection.protocol),
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${connection.protocol.displayName} · '
                      '${connection.host}:${connection.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _protocolIcon(NetworkProtocol p) => switch (p) {
        NetworkProtocol.webdav => Icons.cloud_outlined,
        NetworkProtocol.smb => Icons.folder_shared_outlined,
        NetworkProtocol.ftp => Icons.file_upload_outlined,
      };
}