import 'package:flutter/material.dart';
import 'package:moumou/services/download/download_manager.dart';
import 'package:moumou/services/download/download_task.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/utils/formatters.dart';

/// 下载管理页：任务列表（缩略图/标题/进度条/速度）+ 暂停/恢复/重试/删除。
///
/// 监听 [DownloadManager]（ChangeNotifier），视频与弹幕任务统一在此展示。
class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({super.key});

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  DownloadManager get _manager => DownloadManager.instance;

  Future<void> _confirmClearFinished() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除已完成'),
        content: const Text('只清除已完成和失败的下载记录，不会删除已下载的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _manager.clearFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            onPressed: _confirmClearFinished,
            icon: const Icon(Icons.clear_all),
            tooltip: '清除已完成',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          final tasks = _manager.tasks;
          if (tasks.isEmpty) {
            return const Center(child: Text('暂无下载任务'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: tasks.length,
            itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.isVideo ? Icons.movie_outlined : Icons.subtitles_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (task.subtitle.isNotEmpty)
                        Text(
                          task.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _statusLabel(scheme),
                _actions(scheme),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: task.status == DownloadStatus.failed
                      ? Text(
                          task.error ?? '下载失败',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.error),
                        )
                      : LinearProgressIndicator(
                          // 等待中任务进度为 0：用静态空条而非 value=null，
                          // 避免每张等待卡片的进度条都跑循环动画、闪眼睛（工作.md 第 1 点）。
                          value: task.status == DownloadStatus.pending
                              ? 0
                              : (task.progress > 0 ? task.progress : null),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).round()}%',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                if (task.status == DownloadStatus.downloading &&
                    task.speedBps > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    formatNetworkSpeed(task.speedBps),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLabel(ColorScheme scheme) {
    final (text, color) = switch (task.status) {
      DownloadStatus.completed => ('完成', Colors.green),
      DownloadStatus.failed => ('失败', scheme.error),
      DownloadStatus.paused => ('暂停', scheme.onSurfaceVariant),
      DownloadStatus.merging => ('合并', scheme.tertiary),
      DownloadStatus.downloading => ('下载中', scheme.primary),
      DownloadStatus.pending => ('等待', scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  /// 紧凑操作按钮（32×32，避免默认 48×48 把卡片撑高）。
  Widget _iconBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  Widget _actions(ColorScheme scheme) {
    final muted = scheme.onSurfaceVariant;
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.merging:
        return _iconBtn(
          Icons.pause,
          muted,
          '暂停',
          () => DownloadManager.instance.pause(task.id),
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconBtn(
              Icons.play_arrow,
              scheme.primary,
              '继续',
              () => DownloadManager.instance.resume(task.id),
            ),
            _iconBtn(
              Icons.delete_outline,
              muted,
              '删除',
              () => DownloadManager.instance.remove(task.id),
            ),
          ],
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconBtn(
              Icons.refresh,
              scheme.primary,
              '重试',
              () => DownloadManager.instance.retry(task.id),
            ),
            _iconBtn(
              Icons.delete_outline,
              muted,
              '删除',
              () => DownloadManager.instance.remove(task.id),
            ),
          ],
        );
      case DownloadStatus.completed:
      case DownloadStatus.pending:
        return _iconBtn(
          Icons.delete_outline,
          muted,
          '删除',
          () => DownloadManager.instance.remove(task.id),
        );
    }
  }
}
