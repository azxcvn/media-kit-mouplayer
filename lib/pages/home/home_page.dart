import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/home/folder_detail_page.dart';
import 'package:moumou/pages/home/tree_folder_page.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/video_scanner.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/widgets/folder_card.dart';
import 'package:moumou/widgets/video_card.dart';
import 'package:permission_handler/permission_handler.dart';

/// 首页：展示视频库（列表视图 / 树状视图，两种视图共用同一棵目录树）
class HomePage extends StatefulWidget {
  final ViewSettings viewSettings;

  const HomePage({super.key, required this.viewSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  List<TreeNode> _roots = []; // 树状模式：完整目录树
  List<TreeNode> _folders = []; // 列表模式：含直接视频的文件夹
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });

    // 只检查权限状态，不主动弹权限请求（首次进入由用户点击「授予权限」触发）
    final granted = await _hasStoragePermission();
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }

    // 刷新时清缓存，重新查询 MediaStore（否则新增/删除的视频不生效）
    VideoScanner.clearCache();
    final videos = await VideoScanner.scanVideos();
    final roots = VideoScanner.buildTree(videos); // 树状模式：完整目录树
    final folders = VideoScanner.buildFolderList(videos); // 列表模式：含直接视频的文件夹
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _folders = folders;
      _loading = false;
    });
  }

  /// 检查「允许管理所有文件」权限（低版本 Android 回退到存储权限）
  Future<bool> _hasStoragePermission() async {
    try {
      return await Permission.manageExternalStorage.status.isGranted;
    } catch (_) {
      return await Permission.storage.status.isGranted;
    }
  }

  /// 点击「授予权限」：跳转系统授权界面（允许此 App 管理所有文件），
  /// 授权后自动扫描视频；未授权则停留在提示界面可再次点击
  Future<void> _grantPermission() async {
    bool granted;
    try {
      granted = await Permission.manageExternalStorage
          .request()
          .then((s) => s.isGranted);
    } catch (_) {
      granted = await Permission.storage.request().then((s) => s.isGranted);
    }
    if (granted) {
      await _load();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _showViewOptions() {
    showAppDialog(
      context: context,
      builder: (context) =>
          _ViewOptionsSheet(viewSettings: widget.viewSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('小牛Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '排序与视图',
            onPressed: _showViewOptions,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return _buildMessage(
        icon: Icons.folder_open,
        message: '需要授予存储权限才能扫描视频',
        buttonText: '授予权限',
        buttonIcon: Icons.lock_open,
        onPressed: _grantPermission,
      );
    }
    if (_roots.isEmpty) {
      return _buildMessage(
        icon: Icons.folder_off_outlined,
        message: '没有找到视频',
        buttonText: '重新扫描',
        onPressed: _load,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.viewSettings,
        PlaybackProgressService.instance,
      ]),
      builder: (context, _) {
        if (widget.viewSettings.viewMode == ViewMode.tree) {
          final roots = widget.viewSettings.sortTree(_roots);
          return RefreshIndicator(
            onRefresh: _load,
            child: _buildTree(roots),
          );
        }
        final folders = widget.viewSettings.sortFolders(_folders);
        return RefreshIndicator(
          onRefresh: _load,
          child: _buildList(folders),
        );
      },
    );
  }

  /// 列表视图：只列出文件夹（点进去只显示该文件夹内的视频）
  Widget _buildList(List<TreeNode> folders) {
    return ListView.builder(
      // 底部预留悬浮胶囊空间（系统安全区已由全局 SafeArea 处理）
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final node = folders[index];
        return FolderCard(
          node: node,
          fields: widget.viewSettings.fields,
          onTap: () => _openFolder(node),
        );
      },
    );
  }

  /// 树状视图：一级界面与列表模式一致的文件夹卡片列表（不展开整棵树）。
  /// 文件夹点击进入目录浏览页逐级下钻，视频点击直接播放。
  Widget _buildTree(List<TreeNode> roots) {
    if (roots.isEmpty) {
      return _buildMessage(
        icon: Icons.folder_off_outlined,
        message: '没有找到视频',
        buttonText: '重新扫描',
        onPressed: _load,
      );
    }
    return ListView.builder(
      // 底部预留悬浮胶囊空间（系统安全区已由全局 SafeArea 处理）
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: roots.length,
      itemBuilder: (context, index) {
        final node = roots[index];
        if (node.isFolder) {
          return FolderCard(
            node: node,
            fields: widget.viewSettings.fields,
            onTap: () => _openTreeFolder(node),
          );
        }
        return VideoCard(
          video: node.video!,
          fields: widget.viewSettings.videoFields,
          onTap: () => _openVideo(node.video!),
        );
      },
    );
  }

  /// 树状模式：进入目录浏览页（显示子文件夹 + 视频，可逐级下钻）
  Future<void> _openTreeFolder(TreeNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TreeFolderPage(
          node: node,
          viewSettings: widget.viewSettings,
          path: [node],
        ),
      ),
    );
    // 从目录页返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  Future<void> _openFolder(TreeNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailPage(
          title: node.name,
          videos: node.children.map((c) => c.video!).toList(),
          viewSettings: widget.viewSettings,
        ),
      ),
    );
    // 从详情页返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  Future<void> _openVideo(VideoFile video) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(path: video.path, title: video.name),
      ),
    );
    // 返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  Widget _buildMessage({
    required IconData icon,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
    IconData buttonIcon = Icons.refresh,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(buttonIcon),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

/// 排序弹窗
class _ViewOptionsSheet extends StatelessWidget {
  final ViewSettings viewSettings;

  const _ViewOptionsSheet({required this.viewSettings});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: viewSettings,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('排序', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _sectionTitle(context, '排序方式'),
                  SegmentedButton<SortField>(
                    showSelectedIcon: false,
                    segments: SortField.values
                        .map(
                          (e) => ButtonSegment(value: e, label: Text(e.label)),
                        )
                        .toList(),
                    selected: {viewSettings.sortField},
                    onSelectionChanged: (s) =>
                        viewSettings.setSortField(s.first),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(context, '排序方向'),
                  SegmentedButton<SortOrder>(
                    showSelectedIcon: false,
                    segments: SortOrder.values
                        .map(
                          (e) => ButtonSegment(value: e, label: Text(e.label)),
                        )
                        .toList(),
                    selected: {viewSettings.sortOrder},
                    onSelectionChanged: (s) =>
                        viewSettings.setSortOrder(s.first),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  _sectionTitle(context, '显示字段'),
                  Align(
                    alignment: Alignment.center,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: FolderField.values.map((f) {
                        final selected = viewSettings.fields.contains(f);
                        return FilterChip(
                          label: Text(f.label),
                          selected: selected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) => viewSettings.toggleField(f),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  _sectionTitle(context, '显示模式'),
                  SegmentedButton<ViewMode>(
                    showSelectedIcon: false,
                    // 列表模式在前、树状模式在后
                    segments: [ViewMode.list, ViewMode.tree]
                        .map(
                          (e) => ButtonSegment(value: e, label: Text(e.label)),
                        )
                        .toList(),
                    selected: {viewSettings.viewMode},
                    onSelectionChanged: (s) =>
                        viewSettings.setViewMode(s.first),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
