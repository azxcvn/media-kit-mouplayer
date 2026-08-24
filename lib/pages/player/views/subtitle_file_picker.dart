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
///   支持当前路径显示、名称/大小/日期排序、文件夹记忆
///   （成功导入后记住文件夹，下次打开自动定位）。
///
/// 两者最终都返回「可被 libmpv 直接读取的绝对路径」，失败返回 null。
class SubtitleFileService {
  SubtitleFileService._();

  static const _keyLastFolder = 'subtitle_picker_last_folder';

  /// 记忆的文件夹（成功导入字幕后写入；下次自建选择器打开时定位）
  static Future<String?> getLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastFolder);
  }

  static Future<void> setLastFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastFolder, path);
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

  /// 文件过滤器（只显示目录 + 通过过滤的文件）。默认只显示字幕文件；
  /// 字体导入时传入 [isFontFile] 过滤 .ttf/.otf。
  final bool Function(String filename) fileFilter;

  const SubtitleFilePickerPanel({
    super.key,
    required this.onPicked,
    required this.onClose,
    this.fileFilter = isSupportedSubtitleFile,
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

  @override
  void initState() {
    super.initState();
    _initStartPath();
  }

  Future<void> _initStartPath() async {
    final lastFolder = await SubtitleFileService.getLastFolder();
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

  Future<void> _openFolder(String path) async {
    _currentPath = path;
    await _load();
  }

  Future<void> _goUp() async {
    final parent = _parentOf(_currentPath);
    if (parent == null || parent == _currentPath) return;
    await _openFolder(parent);
  }

  static String? _parentOf(String path) {
    final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = norm.lastIndexOf('/');
    if (idx <= 0) return null;
    return norm.substring(0, idx);
  }

  Future<void> _pickFile(SubtitleDirEntry entry) async {
    await SubtitleFileService.setLastFolder(_currentPath);
    await widget.onPicked(entry.path);
    if (mounted) widget.onClose();
  }

  void _cycleSort() {
    setState(() {
      if (_sort == SubtitleDirSort.name) {
        _sort = SubtitleDirSort.size;
      } else if (_sort == SubtitleDirSort.size) {
        _sort = SubtitleDirSort.date;
      } else {
        _sort = SubtitleDirSort.name;
        _ascending = !_ascending;
      }
      _entries = sortSubtitleDirEntries(_entries, _sort, ascending: _ascending);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 当前路径（可点击上级返回 + 路径显示 + 排序胶囊）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white70, size: 20),
                tooltip: '上一级',
                onPressed: _goUp,
              ),
              Expanded(
                child: Text(
                  _currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _cycleSort,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _ascending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sort.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white24),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.isDirectory
                            ? Icons.folder_rounded
                            : Icons.subtitles_outlined,
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
      ],
    );
  }
}
