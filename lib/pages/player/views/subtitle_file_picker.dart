import 'package:flutter/material.dart';
import 'package:moumou/models/subtitle_track.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/utils/subtitle_sort.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外挂字幕文件选择（工作.md 阶段1 第 3 点）：
///
/// - **Android 11 及以下（SDK ≤ 30）**：调用系统文件选择器
///   （原生 ACTION_OPEN_DOCUMENT，content:// 由原生侧拷贝为真实路径）；
/// - **Android 11 以上（SDK ≥ 31）**：使用自建文件选择器
///   （[SubtitleFilePickerPanel]，作为右侧面板二级页就地切换，不再从底部弹出），
///   支持当前路径显示、名称/大小/日期排序（下拉菜单 + 升降序）、文件夹记忆
///   （成功导入后记住文件夹，下次打开自动定位），以及进出文件夹的滑动动画。
///
/// 两者最终都返回「可被 libmpv 直接读取的绝对路径」，失败返回 null。
class SubtitleFileService {
  SubtitleFileService._();

  static const _keyLastFolder = 'subtitle_picker_last_folder';

  /// 记忆的文件夹（成功导入字幕后写入；下次自建选择器打开时定位）。
  /// [key] 可自定义（音频选择器复用同一面板时传入独立记忆键）。
  static Future<String?> getLastFolder({String key = _keyLastFolder}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> setLastFolder(
    String path, {
    String key = _keyLastFolder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, path);
  }

  /// 系统文件选择器（Android ≤ 11）：content:// 拷贝为应用内真实路径后返回。
  static Future<String?> pickWithSystemPicker() async {
    final uri = await DeviceServices.openDocumentPicker();
    if (uri == null) return null;
    final name = uri.split('/').where((s) => s.isNotEmpty).last;
    final fileName = name.isEmpty ? 'subtitle.srt' : name;
    return DeviceServices.copySubtitleFromUri(uri, fileName);
  }
}

/// 自建字幕文件选择器面板（右侧面板二级页，工作.md 阶段1 第 3 点）。
///
/// - [onPicked]：用户选中一个字幕文件后回调（传入绝对路径），由调用方执行导入；
/// - [onClose]：选择完成/点击关闭后回调，由调用方 pop 当前面板二级页。
///
/// 面板自身无状态，不依赖具体外壳导航器（横屏/竖屏面板通用）。
class SubtitleFilePickerPanel extends StatefulWidget {
  final Future<void> Function(String path) onPicked;
  final VoidCallback onClose;

  /// 文件过滤器（只显示目录 + 通过过滤的文件）。默认只显示字幕文件
  final bool Function(String filename) fileFilter;

  /// 记忆文件夹的 SharedPreferences 键（音频选择器复用本面板时传独立键）
  final String folderKey;

  /// 文件行的图标（字幕选择器默认字幕图标，音频选择器传音乐图标）
  final IconData fileIcon;

  const SubtitleFilePickerPanel({
    super.key,
    required this.onPicked,
    required this.onClose,
    this.fileFilter = isSupportedSubtitleFile,
    this.folderKey = 'subtitle_picker_last_folder',
    this.fileIcon = Icons.subtitles_outlined,
  });

  @override
  State<SubtitleFilePickerPanel> createState() =>
      _SubtitleFilePickerPanelState();
}

class _SubtitleFilePickerPanelState extends State<SubtitleFilePickerPanel> {
  late String _currentPath = '/storage/emulated/0';
  List<SubtitleDirEntry> _entries = const [];
  SubtitleDirSort _sort = SubtitleDirSort.name;
  bool _ascending = true;
  bool _loading = true;

  /// 导航方向：1 = 进入文件夹（前进，新内容从右滑入），
  /// -1 = 返回上一级（后退，新内容从左滑入）。
  int _navDirection = 1;

  @override
  void initState() {
    super.initState();
    _initStartPath();
  }

  Future<void> _initStartPath() async {
    final lastFolder =
        await SubtitleFileService.getLastFolder(key: widget.folderKey);
    if (!mounted) return;
    _currentPath = (lastFolder != null && lastFolder.isNotEmpty)
        ? lastFolder
        : '/storage/emulated/0';
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DeviceServices.listDirectory(_currentPath);
    if (!mounted) return;
    setState(() {
      _entries = sortSubtitleDirEntries(
        entries.where(
          (e) => e.isDirectory || widget.fileFilter(e.name),
        ),
        _sort,
        ascending: _ascending,
      );
      _loading = false;
    });
  }

  Future<void> _openFolder(String path, {int direction = 1}) async {
    _navDirection = direction;
    setState(() => _loading = true);
    final entries = await DeviceServices.listDirectory(path);
    if (!mounted) return;
    setState(() {
      // 内容就绪后再更新路径，使 AnimatedSwitcher 在切换时新旧内容都已正确。
      _currentPath = path;
      _entries = sortSubtitleDirEntries(
        entries.where(
          (e) => e.isDirectory || widget.fileFilter(e.name),
        ),
        _sort,
        ascending: _ascending,
      );
      _loading = false;
    });
  }

  Future<void> _goUp() async {
    final parent = _parentOf(_currentPath);
    if (parent == null || parent == _currentPath) return;
    await _openFolder(parent, direction: -1);
  }

  static String? _parentOf(String path) {
    final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = norm.lastIndexOf('/');
    if (idx <= 0) return null;
    return norm.substring(0, idx);
  }

  /// 路径显示：父路径省略 + 当前文件夹名高亮（始终可见当前层级）。
  Widget _buildPathLabel(String path) {
    final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = norm.lastIndexOf('/');
    final parent = idx > 0 ? norm.substring(0, idx) : '';
    final name = idx >= 0 ? norm.substring(idx + 1) : norm;
    return Row(
      children: [
        if (parent.isNotEmpty)
          Flexible(
            child: Text(
              '$parent/',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ),
        Text(
          name,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFF4FC3F7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile(SubtitleDirEntry entry) async {
    await SubtitleFileService.setLastFolder(_currentPath, key: widget.folderKey);
    await widget.onPicked(entry.path);
    if (mounted) widget.onClose();
  }

  void _setSort(SubtitleDirSort sort, bool ascending) {
    setState(() {
      _sort = sort;
      _ascending = ascending;
      _entries = sortSubtitleDirEntries(_entries, _sort, ascending: _ascending);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶栏：返回上级（文本）+ 当前路径 + 排序菜单 + 升降序
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _goUp,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('上级'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: _buildPathLabel(_currentPath)),
              const SizedBox(width: 8),
              _SortMenu(
                sort: _sort,
                ascending: _ascending,
                onSelect: _setSort,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: Stack(
            children: [
              // 列表：进出文件夹做方向感知的滑动 + 淡入淡出
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: Offset(_navDirection * 0.08, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: ListView.builder(
                  key: ValueKey(_currentPath),
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.isDirectory
                            ? Icons.folder_rounded
                            : widget.fileIcon,
                        size: 22,
                        color: e.isDirectory
                            ? const Color(0xFF64B5F6)
                            : Colors.white70,
                      ),
                      title: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => e.isDirectory
                          ? _openFolder(e.path)
                          : _pickFile(e),
                    );
                  },
                ),
              ),
              // 加载遮罩：覆盖在列表上方，不参与切换动画
              if (_loading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white24),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 排序控件：下拉菜单列出「名称升序 / 名称降序 / 日期升序 / 日期降序」，
/// 当前项以主题色 + 单选标记高亮。
class _SortMenu extends StatelessWidget {
  final SubtitleDirSort sort;
  final bool ascending;
  final void Function(SubtitleDirSort sort, bool ascending) onSelect;

  const _SortMenu({
    required this.sort,
    required this.ascending,
    required this.onSelect,
  });

  String get _label => '${sort.label}${ascending ? '升序' : '降序'}';

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4FC3F7);
    const options = <(SubtitleDirSort, bool)>[
      (SubtitleDirSort.name, true),
      (SubtitleDirSort.name, false),
      (SubtitleDirSort.date, true),
      (SubtitleDirSort.date, false),
    ];
    return PopupMenuButton<(SubtitleDirSort, bool)>(
      onSelected: (v) => onSelect(v.$1, v.$2),
      tooltip: '排序方式',
      color: const Color(0xFF242424),
      itemBuilder: (context) => [
        for (final o in options)
          PopupMenuItem<(SubtitleDirSort, bool)>(
            value: o,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  o == (sort, ascending)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: o == (sort, ascending) ? accent : Colors.white38,
                ),
                const SizedBox(width: 8),
                Text(
                  '${o.$1.label}${o.$2 ? '升序' : '降序'}',
                  style: TextStyle(
                    color: o == (sort, ascending) ? accent : Colors.white,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
