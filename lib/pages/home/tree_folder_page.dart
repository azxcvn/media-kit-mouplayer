import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/media_info/media_info_page.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/folder_card.dart';
import 'package:moumou/widgets/options_sheet.dart';
import 'package:moumou/widgets/video_card.dart';

/// 树状模式的目录浏览页：显示当前文件夹的直接子文件夹（FolderCard）与
/// 直接视频（VideoCard），点击子文件夹继续下钻一层，点击视频直接播放。
///
/// 与列表模式的 FolderDetailPage 不同：本页内容为「文件夹 + 视频」混合，
/// 可逐级深入；列表详情页只显示单个文件夹内的直接视频。
///
/// [path] 为从顶层到当前节点的完整路径链（不含首页），用于面包屑导航：
/// 点击任意上级层级可 popUntil 跳回。
///
/// 右上角从左到右：**搜索**（文件夹 + 视频）→ 排序与字段。
class TreeFolderPage extends StatefulWidget {
  final TreeNode node;
  final ViewSettings viewSettings;
  final List<TreeNode> path;

  const TreeFolderPage({
    super.key,
    required this.node,
    required this.viewSettings,
    this.path = const [],
  });

  @override
  State<TreeFolderPage> createState() => _TreeFolderPageState();
}

class _TreeFolderPageState extends State<TreeFolderPage> {
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 面包屑项：targetIndex 表示要跳回的路径层级（-1 = 首页）
  List<({String label, int targetIndex})> get _crumbs {
    final path = widget.path;
    return [
      (label: '小牛Player', targetIndex: -1),
      for (var i = 0; i < path.length; i++)
        (label: path[i].name, targetIndex: i),
    ];
  }

  void _jumpTo(int targetIndex) {
    if (targetIndex == widget.path.length - 1) return; // 当前页
    final nav = Navigator.of(context);
    if (targetIndex < 0) {
      // 回到首页（树状一级界面）
      nav.popUntil((route) => route.isFirst);
      return;
    }
    // 从当前层 pop 到目标层
    var count = widget.path.length - 1 - targetIndex;
    nav.popUntil((route) {
      if (count == 0) return true;
      count--;
      return false;
    });
  }

  void _showOptions() {
    // 根据页面实际内容动态检测：纯文件夹 / 纯视频 / 混合
    final children = widget.node.children;
    final hasFolders = children.any((c) => c.isFolder);
    final hasVideos = children.any((c) => !c.isFolder);
    showSortOptionsSheet(
      context,
      widget.viewSettings,
      hasFolders: hasFolders,
      hasVideos: hasVideos,
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _openFolder(TreeNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TreeFolderPage(
          node: node,
          viewSettings: widget.viewSettings,
          path: [...widget.path, node],
        ),
      ),
    );
    // 返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  Future<void> _openVideo(VideoFile video) async {
    // 传当前目录的排序视频列表，作为播放页「下一集」的兄弟列表
    final children = widget.viewSettings.sortTree(widget.node.children);
    final playlist = [
      for (final c in children)
        if (!c.isFolder) c.video!,
    ];
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: playerRouteName),
        builder: (_) => PlayerPage(
          path: video.path,
          title: video.name,
          playlist: playlist,
        ),
      ),
    );
    // 返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  void _openMediaInfo(VideoFile video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaInfoPage(path: video.path, title: video.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索文件夹与视频',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              )
            : Text(widget.node.name),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消搜索',
              onPressed: _toggleSearch,
            )
          else if (widget.node.children.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: _toggleSearch,
            ),
          // 目录为空时没有可排序内容，不显示排序入口
          if (widget.node.children.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: '排序与字段',
              onPressed: _showOptions,
            ),
        ],
      ),
      body: Column(
        children: [
          _BreadcrumbBar(crumbs: _crumbs, onTap: _jumpTo),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.node.children.isEmpty) {
      return const Center(child: Text('该文件夹没有视频'));
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.viewSettings,
        PlaybackProgressService.instance,
        PlayerControlsSettings.instance,
      ]),
      builder: (context, _) {
        var children = widget.viewSettings.sortTree(widget.node.children);
        if (_query.isNotEmpty) {
          children = children.where((c) {
            if (c.isFolder) return c.name.toLowerCase().contains(_query);
            return c.video!.name.toLowerCase().contains(_query);
          }).toList();
        }
        if (children.isEmpty && _query.isNotEmpty) {
          return const Center(child: Text('没有匹配的内容'));
        }
        // 底部安全区已由全局 SafeArea 处理
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          itemCount: children.length,
          itemBuilder: (context, index) {
            final child = children[index];
            if (child.isFolder) {
              return FolderCard(
                node: child,
                fields: widget.viewSettings.fields,
                onTap: () => _openFolder(child),
              );
            }
            return VideoCard(
              video: child.video!,
              fields: widget.viewSettings.videoFields,
              onTap: () => _openVideo(child.video!),
              onInfoTap: () => _openMediaInfo(child.video!),
            );
          },
        );
      },
    );
  }
}

/// 顶部面包屑导航栏：横向可滚动，显示「小牛Player → … → 当前目录」路径，
/// 点击任意上级层级跳回对应页面（参考 mpvRx 的 BreadcrumbNavigation）。
class _BreadcrumbBar extends StatefulWidget {
  final List<({String label, int targetIndex})> crumbs;
  final void Function(int targetIndex) onTap;

  const _BreadcrumbBar({required this.crumbs, required this.onTap});

  @override
  State<_BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<_BreadcrumbBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 首次进入（新 push 的目录页）也要自动滚动到末尾，
    // 让当前层级的名称立即可见并高亮
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_BreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.crumbs.length != widget.crumbs.length) {
      // 路径变化时自动滚动到末尾（对齐 mpvRx 行为）
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (mounted && _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final crumbs = widget.crumbs;
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++)
            ..._buildCrumb(scheme, crumbs[i], i, crumbs.length),
        ],
      ),
    );
  }

  List<Widget> _buildCrumb(
    ColorScheme scheme,
    ({String label, int targetIndex}) crumb,
    int index,
    int total,
  ) {
    final isCurrent = index == total - 1;
    final widgets = <Widget>[
      TextButton(
        onPressed: isCurrent ? null : () => widget.onTap(crumb.targetIndex),
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: isCurrent
              ? scheme.primary
              : scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.primary,
        ),
        child: Text(
          crumb.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    ];
    if (!isCurrent) {
      widgets.add(
        Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
      );
    }
    return widgets;
  }
}
