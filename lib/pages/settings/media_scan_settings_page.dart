import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/media_scan_settings.dart';
import 'package:moumou/services/video_scanner.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 媒体扫描与过滤设置页（对齐 mpvRx 与小喵 player）：
/// - 扫描规则（.nomedia 目录 / .开头隐藏文件夹）；
/// - 文件夹黑白名单过滤模式；
/// - 黑白名单文件夹列表管理与目录选择添加。
class MediaScanSettingsPage extends StatefulWidget {
  const MediaScanSettingsPage({super.key});

  @override
  State<MediaScanSettingsPage> createState() => _MediaScanSettingsPageState();
}

class _MediaScanSettingsPageState extends State<MediaScanSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = MediaScanSettings.instance;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体扫描与过滤'),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final mode = settings.filterMode;
          final isBlacklist = mode == FolderFilterMode.blacklist;
          final isWhitelist = mode == FolderFilterMode.whitelist;
          final currentList = isBlacklist
              ? settings.blacklistFolders
              : (isWhitelist ? settings.whitelistFolders : const <String>[]);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ── 扫描规则 ──────────────────────────────────────────
              const SettingsGroupTitle(title: '扫描规则'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.visibility_off_outlined,
                      title: '扫描包含 .nomedia 的文件夹',
                      subtitle: const Text('扫描系统忽略的目录'),
                      value: settings.scanNoMedia,
                      onChanged: (val) async {
                        if (val) {
                          final confirmed = await _showNoMediaWarningDialog(context);
                          if (!confirmed) return;
                        }
                        await settings.setScanNoMedia(val);
                        VideoScanner.clearCache();
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsSwitchTile(
                      icon: Icons.folder_special_outlined,
                      title: '扫描以 . 开头的隐藏文件夹',
                      subtitle: const Text('扫描隐藏文件'),
                      value: settings.scanHiddenFolders,
                      onChanged: (val) async {
                        await settings.setScanHiddenFolders(val);
                        VideoScanner.clearCache();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 文件夹过滤模式 ────────────────────────────────────
              const SettingsGroupTitle(title: '文件夹过滤模式'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsRadioTile(
                      icon: Icons.all_inclusive,
                      title: '全部扫描',
                      subtitle: const Text('扫描所有未跳过的文件夹'),
                      selected: mode == FolderFilterMode.none,
                      onTap: () async {
                        await settings.setFilterMode(FolderFilterMode.none);
                        VideoScanner.clearCache();
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsRadioTile(
                      icon: Icons.block_outlined,
                      title: '黑名单模式',
                      subtitle: const Text('排除指定文件夹'),
                      selected: mode == FolderFilterMode.blacklist,
                      onTap: () async {
                        await settings.setFilterMode(FolderFilterMode.blacklist);
                        VideoScanner.clearCache();
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsRadioTile(
                      icon: Icons.check_box_outlined,
                      title: '白名单模式',
                      subtitle: const Text('仅扫描指定文件夹'),
                      selected: mode == FolderFilterMode.whitelist,
                      onTap: () async {
                        await settings.setFilterMode(FolderFilterMode.whitelist);
                        VideoScanner.clearCache();
                      },
                    ),
                  ],
                ),
              ),

              // ── 黑/白名单文件夹列表管理 ────────────────────────────
              if (isBlacklist || isWhitelist) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SettingsGroupTitle(
                      title: isBlacklist ? '黑名单文件夹列表' : '白名单文件夹列表',
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _openFolderPicker(context, isBlacklist),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加文件夹'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (currentList.isEmpty)
                  SettingsCard(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        isBlacklist
                            ? '暂无黑名单文件夹（未排除任何目录）'
                            : '暂无白名单文件夹（未添加时默认显示全部）',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  SettingsCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < currentList.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isBlacklist
                                    ? scheme.errorContainer
                                    : scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isBlacklist
                                    ? Icons.folder_off_outlined
                                    : Icons.folder_outlined,
                                size: 20,
                                color: isBlacklist
                                    ? scheme.onErrorContainer
                                    : scheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              _folderNameOf(currentList[i]),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              currentList[i],
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: scheme.error,
                              onPressed: () async {
                                if (isBlacklist) {
                                  await settings.removeBlacklistFolder(currentList[i]);
                                } else {
                                  await settings.removeWhitelistFolder(currentList[i]);
                                }
                                VideoScanner.clearCache();
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 提取文件夹路径的最后一段名称
  static String _folderNameOf(String path) {
    final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final i = clean.lastIndexOf('/');
    return i >= 0 ? clean.substring(i + 1) : clean;
  }

  /// 开启 .nomedia 扫描时的提示弹窗（参考小喵 player）
  static Future<bool> _showNoMediaWarningDialog(BuildContext context) async {
    final result = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启提示'),
        content: const Text(
          '此功能将扫描系统默认忽略的 .nomedia 文件夹。\n\n'
          '开启后，某些应用程序的缓存视频、临时文件或表情包也可能被展示在媒体列表中。是否继续？',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定开启'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 打开文件夹选择器并添加路径（优先展示已扫描到的媒体文件夹，对齐 mpvRx）
  Future<void> _openFolderPicker(BuildContext context, bool isBlacklist) async {
    final settings = MediaScanSettings.instance;
    final currentList = isBlacklist
        ? settings.blacklistFolders
        : settings.whitelistFolders;

    final selectedPath = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CandidateFoldersSheet(
        existingFolders: currentList,
        isBlacklist: isBlacklist,
      ),
    );

    if (selectedPath != null && selectedPath.isNotEmpty) {
      if (isBlacklist) {
        await settings.addBlacklistFolder(selectedPath);
      } else {
        await settings.addWhitelistFolder(selectedPath);
      }
      VideoScanner.clearCache();
    }
  }
}

/// 优先展示「全部扫描」发现的媒体文件夹列表（对齐 mpvRx 设计）
class _CandidateFoldersSheet extends StatefulWidget {
  final List<String> existingFolders;
  final bool isBlacklist;

  const _CandidateFoldersSheet({
    required this.existingFolders,
    required this.isBlacklist,
  });

  @override
  State<_CandidateFoldersSheet> createState() => _CandidateFoldersSheetState();
}

class _CandidateFoldersSheetState extends State<_CandidateFoldersSheet> {
  List<TreeNode> _folderList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() => _loading = true);
    try {
      final allVideos = await VideoScanner.scanVideos(
        scanSettings: MediaScanSettings.unfiltered,
      );
      final folders = VideoScanner.buildFolderList(allVideos);
      if (!mounted) return;
      setState(() {
        _folderList = folders;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filteredCandidates = _folderList
        .where((f) => !widget.existingFolders.contains(f.path))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部标题
          Row(
            children: [
              Icon(
                widget.isBlacklist ? Icons.folder_off_outlined : Icons.folder_outlined,
                size: 22,
                color: widget.isBlacklist ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isBlacklist ? '添加黑名单文件夹' : '添加白名单文件夹',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isBlacklist
                ? '选择要排除的媒体文件夹（点击直接添加）：'
                : '选择要仅保留扫描的媒体文件夹（点击直接添加）：',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredCandidates.isEmpty
                    ? Center(
                        child: Text(
                          '未发现更多媒体文件夹',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredCandidates.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                        itemBuilder: (context, i) {
                          final f = filteredCandidates[i];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.folder, color: scheme.primary, size: 22),
                            ),
                            title: Text(
                              f.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${f.path}\n${f.videoCount} 个视频',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                            trailing: const Icon(Icons.add_circle_outline, size: 22),
                            onTap: () => Navigator.of(context).pop(f.path),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final customPath = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (ctx) => const _FolderPickerSheet(),
              );
              if (customPath != null && context.mounted) {
                Navigator.of(context).pop(customPath);
              }
            },
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
            label: const Text('浏览设备其他目录...'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部弹出的文件夹导航选择器
class _FolderPickerSheet extends StatefulWidget {
  const _FolderPickerSheet();

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  String _currentPath = '/storage/emulated/0';
  List<SubtitleDirEntry> _subFolders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() => _loading = true);
    final entries = await DeviceServices.listDirectory(_currentPath);
    if (!mounted) return;
    setState(() {
      _subFolders = entries.where((e) => e.isDirectory).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loading = false;
    });
  }

  void _navigateUp() {
    if (_currentPath == '/storage/emulated/0' || _currentPath == '/storage') return;
    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    if (parent.isNotEmpty) {
      _currentPath = parent;
      _loadDirectory();
    }
  }

  void _navigateTo(String subDirName) {
    _currentPath = '$_currentPath/$subDirName'.replaceAll(RegExp(r'/+'), '/');
    _loadDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRoot = _currentPath == '/storage/emulated/0' || _currentPath == '/storage';

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部标题栏 + 关闭
          Row(
            children: [
              const Icon(Icons.create_new_folder_outlined, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '选择文件夹',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          // 当前路径与上一级按钮
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: isRoot ? null : _navigateUp,
                  tooltip: '上一级',
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 子文件夹列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _subFolders.isEmpty
                    ? Center(
                        child: Text(
                          '当前目录下无子文件夹',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _subFolders.length,
                        itemBuilder: (context, index) {
                          final folder = _subFolders[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.folder, color: scheme.primary),
                            title: Text(folder.name),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _navigateTo(folder.name),
                          );
                        },
                      ),
          ),

          const SizedBox(height: 12),

          // 确认选择当前文件夹按钮
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_currentPath),
            icon: const Icon(Icons.check),
            label: Text('选择当前文件夹 (${_folderNameOf(_currentPath)})'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  static String _folderNameOf(String path) {
    final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final i = clean.lastIndexOf('/');
    return i >= 0 ? clean.substring(i + 1) : clean;
  }
}
