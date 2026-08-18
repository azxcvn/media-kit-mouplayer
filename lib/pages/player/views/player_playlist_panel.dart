import 'package:flutter/material.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/widgets/player_option_chip.dart';

/// 播放列表面板内容（通过 [showPlayerPanel] 右侧滑入，标题「播放列表」）。
///
/// 参考 kt 项目 `VideoListDrawer.kt`：
/// - 顶部 4 个排序胶囊一行（名称升序/名称降序/日期升序/日期降序），
///   点击重排（[sortVideosForPlaylist]），排序状态为**面板局部状态**
///   （每次打开默认名称升序）；
/// - 列表项 = 序号 + 文件名，当前播放项以主题色高亮（文字 + 「播放中」徽标）；
/// - 排序切换后自动滚动定位到当前项（固定行高 52，滚动偏移精确计算）；
/// - 点击列表项 → [onSelect] 回调（播放页统一切集，自带进度记忆与
///   新集进度恢复），随后面板自行关闭。
///
/// ⚠️ 面板是独立弹窗路由，播放页 setState 不会重建它：排序状态、滚动
/// 定位、当前项高亮全部在本 State 内部自行管理。
class PlayerPlaylistPanel extends StatefulWidget {
  /// 当前视频所在文件夹的视频列表（调用方已按同目录过滤）
  final List<VideoFile> videos;

  /// 当前播放视频路径（高亮与滚动定位依据）
  final String currentPath;

  /// 点击列表项回调（由播放页执行切集；当前项点击也会触发，调用方自行忽略）
  final ValueChanged<VideoFile> onSelect;

  const PlayerPlaylistPanel({
    super.key,
    required this.videos,
    required this.currentPath,
    required this.onSelect,
  });

  @override
  State<PlayerPlaylistPanel> createState() => _PlayerPlaylistPanelState();
}

class _PlayerPlaylistPanelState extends State<PlayerPlaylistPanel> {
  /// 固定行高：滚动定位按 `索引 × 行高` 精确计算
  static const double _itemExtent = 52;

  /// 排序状态为面板局部状态：每次打开默认名称升序
  PlaylistSortMode _sortMode = PlaylistSortMode.nameAsc;
  late List<VideoFile> _sorted;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sorted = sortVideosForPlaylist(widget.videos, _sortMode);
    // 打开后先滚动到当前项（等首帧布局完成）
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setSortMode(PlaylistSortMode mode) {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
      _sorted = sortVideosForPlaylist(widget.videos, mode);
    });
    // 排序变化后保持当前项可见（src VideoListDrawer 的 animateScrollToItem 思路）
    _scrollToCurrent();
  }

  /// 滚动定位到当前项（固定行高：目标偏移 = 索引 × 行高，钳制到可视范围）
  void _scrollToCurrent() {
    final idx = _sorted.indexWhere((v) => v.path == widget.currentPath);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final target = (idx * _itemExtent).clamp(0.0, max);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handleSelect(VideoFile video) {
    widget.onSelect(video);
    // 点击后关闭面板（src 同款：延迟切换后关闭抽屉）
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSortRow(),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _sorted.isEmpty
              ? const Center(
                  child: Text(
                    '当前文件夹没有其他视频',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemExtent: _itemExtent,
                  itemCount: _sorted.length,
                  itemBuilder: (context, index) =>
                      _buildItem(context, index),
                ),
        ),
      ],
    );
  }

  /// 顶部排序胶囊行：4 个胶囊一行（名称升序/名称降序/日期升序/日期降序）
  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          for (final mode in PlaylistSortMode.values) ...[
            if (mode != PlaylistSortMode.values.first)
              const SizedBox(width: 6),
            Expanded(
              child: PlayerOptionChip(
                label: mode.label,
                selected: _sortMode == mode,
                textAlign: TextAlign.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                onTap: () => _setSortMode(mode),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 列表项：序号 + 文件名 +（当前项）主题色高亮与「播放中」徽标
  Widget _buildItem(BuildContext context, int index) {
    final video = _sorted[index];
    final isCurrent = video.path == widget.currentPath;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _handleSelect(video),
      child: Container(
        height: _itemExtent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isCurrent ? scheme.primary : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                video.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? scheme.primary : Colors.white,
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '播放中',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
