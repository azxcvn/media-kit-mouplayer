import 'package:flutter/material.dart';
import 'package:moumou/services/cache_manager_service.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 缓存管理页（设置 → 关于 → 工具 → 缓存管理）：
/// 展示各类缓存占用，支持逐类清除与「一键清除所有缓存」（二次确认），
/// 右上角刷新按钮 + 下拉刷新可重新读取当前缓存大小。
class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  Map<String, int> _sizes = const {};
  bool _loading = false;

  /// 各类别图标（服务层不依赖 UI，图标放页面层）
  static const _icons = {
    'scrubThumbs': Icons.image_outlined,
    'listThumbs': Icons.video_library_outlined,
    'other': Icons.folder_zip_outlined,
  };

  int get _totalBytes => _sizes.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final sizes = await CacheManagerService.getCacheSizes();
    if (!mounted) return;
    setState(() {
      _sizes = sizes;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 统一确认弹窗（返回是否确认）
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

  Future<void> _clearCategory(CacheCategory category) async {
    final size = _sizes[category.key] ?? 0;
    final confirmed = await _confirm(
      '清除${category.label}',
      '将删除「${category.label}」缓存（${formatFileSize(size)}），确定？',
    );
    if (!confirmed) return;
    final ok = await CacheManagerService.clearCategory(category);
    _toast(ok ? '已清除${category.label}' : '清除失败');
    _refresh();
  }

  /// 一键清除所有缓存：二次弹窗确认
  Future<void> _clearAll() async {
    final first = await _confirm(
      '清除所有缓存',
      '将删除全部缓存（当前共 ${formatFileSize(_totalBytes)}）：\n'
      '· 进度条视频缩略图\n· 视频列表封面缩略图\n· 其他缓存\n\n此操作不可恢复。',
    );
    if (!first) return;
    final second = await _confirm('再次确认', '确定要清除所有缓存吗？');
    if (!second) return;
    final ok = await CacheManagerService.clearAll();
    _toast(ok ? '已清除全部缓存' : '清除失败');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            const SettingsGroupTitle(title: '缓存'),
            SettingsCard(
              child: Column(
                children: [
                  for (final category in CacheManagerService.all) ...[
                    if (category != CacheManagerService.all.first)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(
                        _icons[category.key] ?? Icons.folder_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        category.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        _loading ? '读取中…' : formatFileSize(_sizes[category.key] ?? 0),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed:
                            _loading ? null : () => _clearCategory(category),
                        child: const Text('清除'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 一键清除所有缓存（危险操作，二次确认）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _loading ? null : _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(
                  '一键清除所有缓存（${formatFileSize(_totalBytes)}）',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '进度条缩略图缓存随播放自动生成（可在「播放器设置」关闭该功能）；'
                '列表封面缩略图会在下次扫描时重新生成。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
