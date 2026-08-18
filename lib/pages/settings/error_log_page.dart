import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moumou/services/crash_log_service.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 错误日志页（设置 → 关于 → 工具 → 错误日志）：
/// 崩溃日志由原生 CrashHandler 自动记录到 `files/crash_logs/`。
///
/// - 日志文件**竖向排列**，显示名称 / 时间 / 大小；
/// - 点击日志进入详情：**实时查看**（进入即读最新内容，可手动刷新）、
///   **一键复制**、**导出**（复制到公共 Download/moumou_logs/）；
/// - 页面顶部展示日志保存路径；
/// - 支持删除单个日志与清空全部（二次确认）。
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  List<CrashLogFile> _logs = const [];
  String? _logDir;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = _logs.isEmpty);
    final dir = await CrashLogService.getLogDir();
    final logs = await CrashLogService.listLogs();
    if (!mounted) return;
    setState(() {
      _logDir = dir;
      _logs = logs;
      _loading = false;
      _refreshing = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openLog(CrashLogFile log) async {
    final content = await CrashLogService.readLog(log.path);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LogDetailPage(
          log: log,
          initialContent: content,
        ),
      ),
    );
  }

  Future<void> _copyLog(CrashLogFile log) async {
    final content = await CrashLogService.readLog(log.path);
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) _toast('日志内容已复制到剪贴板');
  }

  Future<void> _exportLog(CrashLogFile log) async {
    final dst = await CrashLogService.exportLog(log.path);
    if (!mounted) return;
    if (dst == null) {
      _toast('导出失败');
      return;
    }
    _toast('已导出到\n$dst');
  }

  Future<bool> _confirm(String title, String content) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteLog(CrashLogFile log) async {
    final confirmed = await _confirm('删除日志', '确定删除「${log.name}」吗？');
    if (!confirmed) return;
    final ok = await CrashLogService.deleteLog(log.path);
    _toast(ok ? '已删除' : '删除失败');
    _refresh();
  }

  Future<void> _clearAll() async {
    final first = await _confirm('清空全部日志', '将删除全部 ${_logs.length} 个日志文件，此操作不可恢复。');
    if (!first) return;
    final ok = await CrashLogService.clearLogs();
    _toast(ok ? '已清空全部日志' : '清空失败');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错误日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refreshing
                ? null
                : () {
                    setState(() => _refreshing = true);
                    _refresh();
                  },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        // 保存路径（顶部展示）
        if (_logDir != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '日志保存路径：\n$_logDir',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SettingsGroupTitle(title: '崩溃日志（${_logs.length}）'),
        if (_logs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.3,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无错误日志',
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '应用崩溃时日志会自动记录到这里',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SettingsCard(
            child: Column(
              children: [
                for (final log in _logs) ...[
                  if (log != _logs.first)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _LogTile(
                    log: log,
                    onTap: () => _openLog(log),
                    onCopy: () => _copyLog(log),
                    onExport: () => _exportLog(log),
                    onDelete: () => _deleteLog(log),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _logs.isEmpty ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text(
                '清空全部日志',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 日志文件行（竖向排列）：名称 + 时间·大小 + 操作（复制/导出/删除）
class _LogTile extends StatelessWidget {
  final CrashLogFile log;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _LogTile({
    required this.log,
    required this.onTap,
    required this.onCopy,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dt = log.modifiedAt;
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.description_outlined,
                size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$date · ${formatFileSize(log.size)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '一键复制',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, size: 18),
              tooltip: '导出',
              visualDensity: VisualDensity.compact,
              onPressed: onExport,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              color: scheme.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 日志详情页：实时查看（进入即读最新内容 + 手动刷新）、一键复制、导出。
class _LogDetailPage extends StatefulWidget {
  final CrashLogFile log;
  final String initialContent;

  const _LogDetailPage({
    required this.log,
    required this.initialContent,
  });

  @override
  State<_LogDetailPage> createState() => _LogDetailPageState();
}

class _LogDetailPageState extends State<_LogDetailPage> {
  late String _content;

  @override
  void initState() {
    super.initState();
    _content = widget.initialContent;
  }

  Future<void> _reload() async {
    final content = await CrashLogService.readLog(widget.log.path);
    if (mounted) setState(() => _content = content);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('日志内容已复制到剪贴板'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _export() async {
    final dst = await CrashLogService.exportLog(widget.log.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(dst == null ? '导出失败' : '已导出到\n$dst'),
          duration: const Duration(milliseconds: 2000),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.log.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新（实时查看）',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'copy',
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            label: const Text('一键复制'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'export',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
            label: const Text('导出'),
          ),
        ],
      ),
    );
  }
}
