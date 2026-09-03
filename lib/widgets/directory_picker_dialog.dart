import 'package:flutter/material.dart';
import 'package:moumou/services/device_services.dart';

/// 弹出目录选择器，返回用户选中的**真实目录路径**；取消返回 null。
///
/// 复用 [DeviceServices.listDirectory]（死路径返回 null 自动向上回退），
/// 只展示子目录、点目录进入、点「选择此目录」确认当前目录。供下载目录设置、
/// 字幕/弹幕选择等场景复用。
Future<String?> showDirectoryPickerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _DirectoryPickerDialog(),
  );
}

class _DirectoryPickerDialog extends StatefulWidget {
  const _DirectoryPickerDialog();

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  static const String _defaultRoot = '/storage/emulated/0';

  String _currentPath = _defaultRoot;
  List<SubtitleDirEntry> _dirs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_defaultRoot);
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final entries = await DeviceServices.listDirectory(path);
    if (!mounted) return;
    if (entries == null) {
      setState(() {
        _error = '目录不可读或不存在';
        _loading = false;
      });
      return;
    }
    final dirs = entries.where((e) => e.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _currentPath = path;
      _dirs = dirs;
      _loading = false;
    });
  }

  String? get _parent {
    final norm = _currentPath.endsWith('/')
        ? _currentPath.substring(0, _currentPath.length - 1)
        : _currentPath;
    final idx = norm.lastIndexOf('/');
    if (idx <= 0) return null;
    final parent = norm.substring(0, idx);
    return parent.isEmpty ? '/' : parent;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择下载目录'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _parent == null ? null : () => _load(_parent!),
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: '上级目录',
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          child: const Text('选择此目录'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_dirs.isEmpty) {
      return const Center(child: Text('该目录下没有子目录'));
    }
    return ListView.builder(
      itemCount: _dirs.length,
      itemBuilder: (_, i) {
        final e = _dirs[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.folder_outlined),
          title: Text(e.name, overflow: TextOverflow.ellipsis),
          onTap: () => _load(e.path),
        );
      },
    );
  }
}
