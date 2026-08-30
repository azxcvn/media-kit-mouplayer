import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/home/folder_detail_page.dart';
import 'package:moumou/pages/home/tree_folder_page.dart';
import 'package:moumou/pages/home/views/folder_list_view.dart';
import 'package:moumou/pages/home/views/tree_list_view.dart';
import 'package:moumou/pages/media_info/media_info_page.dart';
import 'package:moumou/pages/network/network_storage_page.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/video_scanner.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/options_sheet.dart';
import 'package:moumou/widgets/speed_dial_fab.dart';
import 'package:permission_handler/permission_handler.dart';

/// 首页：展示视频库（列表视图 / 树状视图，两种视图共用同一棵目录树）。
///
/// 右上角从左到右：**搜索**（文件夹 + 视频文件名过滤）→ 排序与字段。
class HomePage extends StatefulWidget {
  final ViewSettings viewSettings;

  const HomePage({super.key, required this.viewSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<TreeNode> _roots = []; // 树状模式：完整目录树
  List<TreeNode> _folders = []; // 列表模式：含直接视频的文件夹
  bool _loading = true;
  bool _permissionDenied = false;

  /// 搜索状态：false = 正常标题栏；true = 显示搜索输入框
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统文件管理器或其他应用切回时，自动刷新视频列表（感知外部重命名/移动/删除）
    if (state == AppLifecycleState.resumed && mounted && !_loading) {
      _load();
    }
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
    // 建树 / 建文件夹列表移到后台 isolate（compute）执行：排序、建树、聚合
    // 是同步纯函数，视频量几千条时在 UI 线程跑会有几十毫秒级卡顿
    // （risk_audit #6）。TreeNode/VideoFile 均为纯数据（String/int/DateTime/
    // List），可跨 isolate 传输；两条计算并行发起的独立 isolate。
    final rootsFuture = compute(VideoScanner.buildTree, videos); // 树状模式：完整目录树
    final foldersFuture =
        compute(VideoScanner.buildFolderList, videos); // 列表模式：含直接视频的文件夹
    final roots = await rootsFuture;
    final folders = await foldersFuture;
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
    showSortOptionsSheet(
      context,
      widget.viewSettings,
      hasFolders: true,
      hasVideos: false,
      showViewMode: true,
    );
  }

  // ── 搜索 ──────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  void _onQueryChanged(String v) => setState(() => _query = v.trim().toLowerCase());

  /// 按名称过滤（不区分大小写）
  bool _matchName(String name) {
    if (_query.isEmpty) return true;
    return name.toLowerCase().contains(_query);
  }

  /// 树状模式过滤：递归过滤（文件夹名匹配保留整棵子树；视频名匹配保留自身）
  List<TreeNode> _filterTree(List<TreeNode> nodes) {
    final result = <TreeNode>[];
    for (final n in nodes) {
      if (n.isFolder) {
        final children = _filterTree(n.children);
        if (children.isNotEmpty || _matchName(n.name)) {
          result.add(_rebuildFolder(n, children));
        }
      } else if (_matchName(n.name)) {
        result.add(n);
      }
    }
    return result;
  }

  TreeNode _rebuildFolder(TreeNode n, List<TreeNode> children) {
    if (identical(children, n.children)) return n;
    return TreeNode(
      name: n.name,
      path: n.path,
      type: n.type,
      children: children,
      videoCount: n.videoCount,
      totalSize: n.totalSize,
      dateModified: n.dateModified,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                onChanged: _onQueryChanged,
              )
            : const Text('小牛Player'),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消搜索',
              onPressed: _toggleSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: _toggleSearch,
            ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '排序与视图',
            onPressed: _showViewOptions,
          ),
        ],
      ),
      body: _buildBody(),
      // 右下角加号略高于悬浮胶囊导航栏（与网络存储页保持同一高度）
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: kFabLiftAboveNav),
        child: _buildSpeedDial(),
      ),
    );
  }

  /// 右下角速拨按钮：最近播放 / 打开链接 / 哔哩番剧 / 网络存储。
  /// 仅「网络存储」已接入，其余三项预留入口后续实现。
  Widget _buildSpeedDial() {
    return SpeedDialFab(
      heroTag: 'home_speed_dial',
      actions: [
        SpeedDialAction(
          icon: Icons.history,
          label: '最近播放',
          onTap: () => _comingSoon('最近播放'),
        ),
        SpeedDialAction(
          icon: Icons.link,
          label: '打开链接',
          onTap: () => _comingSoon('打开链接'),
        ),
        SpeedDialAction(
          icon: Icons.live_tv_outlined,
          label: '哔哩番剧',
          onTap: () => _comingSoon('哔哩番剧'),
        ),
        SpeedDialAction(
          icon: Icons.cloud_outlined,
          label: '网络存储',
          onTap: _openNetworkStorage,
        ),
      ],
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('「$feature」功能正在开发中，敬请期待')),
      );
  }

  Future<void> _openNetworkStorage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkStoragePage()),
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
        PlayerControlsSettings.instance,
      ]),
      builder: (context, _) {
        if (widget.viewSettings.viewMode == ViewMode.tree) {
          var roots = widget.viewSettings.sortTree(_roots);
          if (_query.isNotEmpty) roots = _filterTree(roots);
          if (roots.isEmpty && _query.isNotEmpty) {
            return const Center(child: Text('没有匹配的内容'));
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: TreeListView(
              roots: roots,
              folderFields: widget.viewSettings.fields,
              videoFields: widget.viewSettings.videoFields,
              onFolderTap: _openTreeFolder,
              onVideoTap: _openVideo,
              onVideoInfoTap: _openMediaInfo,
            ),
          );
        }
        var folders = widget.viewSettings.sortFolders(_folders);
        if (_query.isNotEmpty) {
          folders = folders.where((n) => _matchName(n.name)).toList();
          if (folders.isEmpty) {
            return const Center(child: Text('没有匹配的文件夹'));
          }
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: FolderListView(
            folders: folders,
            fields: widget.viewSettings.fields,
            onFolderTap: _openFolder,
          ),
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
    // 传首页一级界面的排序视频列表（树状模式根层视频），作为「下一集」的兄弟列表
    final roots = widget.viewSettings.sortTree(_roots);
    final playlist = [
      for (final c in roots)
        if (!c.isFolder) c.video!,
    ];
    await Navigator.of(context).push(
      playerPageRoute(PlayerPage(
        path: video.path,
        title: video.name,
        playlist: playlist,
      )),
    );
    // 返回后刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  /// 打开媒体信息页（点击视频卡片最右侧的「i」）
  void _openMediaInfo(VideoFile video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaInfoPage(path: video.path, title: video.name),
      ),
    );
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
