import 'package:flutter/material.dart';
import 'package:moumou/models/network_connection.dart';
import 'package:moumou/models/network_file.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/services/network/network_repository.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/utils/natural_compare.dart';
import 'package:moumou/utils/network_mime_types.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/folder_card.dart';
import 'package:moumou/widgets/video_card.dart';

/// 在线目录浏览页：复用主页的 FolderCard / VideoCard 呈现远端文件夹与视频列表。
///
/// 与本地「目录浏览页」一致：文件夹逐级下钻（页面内维护面包屑栈），视频点击
/// 经 loopback 代理注册后交给播放器播放。
class NetworkBrowserPage extends StatefulWidget {
  final NetworkConnection connection;

  const NetworkBrowserPage({super.key, required this.connection});

  @override
  State<NetworkBrowserPage> createState() => _NetworkBrowserPageState();
}

class _NetworkBrowserPageState extends State<NetworkBrowserPage> {
  late final List<String> _stack;
  List<NetworkFile> _entries = [];
  bool _loading = true;
  String? _error;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    // 路径字段语义因协议而异，必须区分，否则会拼出双份路径（如 /dav/dav/ → 404）：
    // - SMB：connection.path 是「初始目录/共享名」（SMB 客户端不把它当基前缀），
    //   填 `/共享名` 时跳过列共享、直接进入该共享（部分 Windows 拒绝列共享、只能直连共享）；
    // - FTP/WebDAV：connection.path 是「根路径基前缀」（客户端请求时会再拼一层），
    //   浏览必须从 `/` 开始，才能拼成 connection.path + /xxx。
    final p = widget.connection.path;
    final initial = widget.connection.protocol == NetworkProtocol.smb
        ? ((p.isEmpty || p == '/') ? '/' : p)
        : '/';
    _stack = [initial];
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await NetworkRepository.instance
          .browse(widget.connection, _path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is NetworkClientException ? e.message : '连接失败：$e';
        _loading = false;
      });
    }
  }

  void _openFolder(NetworkFile folder) {
    setState(() {
      _stack.add(folder.path);
      _entries = [];
    });
    _load();
  }

  void _popLevel() {
    if (_stack.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _stack.removeLast();
      _entries = [];
    });
    _load();
  }

  Future<void> _openVideo(VideoFile video) async {
    final url = await NetworkRepository.instance.playbackUrl(
      widget.connection,
      video.remotePath!,
      fileSize: video.size > 0 ? video.size : -1,
      mimeType: networkMimeTypeForFileName(video.name) ?? 'video/mp4',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      playerPageRoute(PlayerPage(path: url, title: video.name)),
    );
    await NetworkRepository.instance.releasePlayback(url);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 拦截系统返回键/手势，与左上角返回一致：逐级回上一级目录，
      // 到根（_stack 只剩一层）时才真正退出本页。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popLevel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _popLevel),
          title: Text(_title()),
        ),
        body: _buildBody(),
      ),
    );
  }

  String _title() {
    if (_path == '/') return widget.connection.name;
    final segments = _path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? widget.connection.name : segments.last;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        icon: Icons.error_outline,
        message: _error!,
        buttonText: '重试',
        onPressed: _load,
      );
    }
    if (_entries.isEmpty) {
      return _message(
        icon: Icons.folder_off_outlined,
        message: '该目录为空',
        buttonText: '返回上一级',
        onPressed: _popLevel,
      );
    }

    final folders = _entries.where((e) => e.isDirectory).toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    final videos = _entries
        .where((e) => !e.isDirectory && isNetworkVideoFile(e.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    // 非视频文件（字幕 / 图片 / 文本等）同样列出，只是不可点击——避免目录
    // 只含非视频文件时出现「点进去一片空白」的问题。
    final others = _entries
        .where((e) => !e.isDirectory && !isNetworkVideoFile(e.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));

    final foldersEnd = folders.length;
    final videosEnd = foldersEnd + videos.length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: foldersEnd + videos.length + others.length,
      itemBuilder: (context, index) {
        if (index < foldersEnd) {
          final folder = folders[index];
          return FolderCard(
            node: _toFolderNode(folder),
            fields: const {},
            onTap: () => _openFolder(folder),
          );
        }
        if (index < videosEnd) {
          final video = videos[index - foldersEnd];
          return VideoCard(
            video: _toVideoFile(video),
            fields: const {VideoField.size},
            onTap: () => _openVideo(_toVideoFile(video)),
          );
        }
        return _OtherFileTile(file: others[index - videosEnd]);
      },
    );
  }

  TreeNode _toFolderNode(NetworkFile f) => TreeNode(
        name: f.name,
        path: f.path,
        type: TreeNodeType.folder,
        children: const [],
        videoCount: 0,
        totalSize: f.size,
        dateModified: f.lastModified > 0
            ? DateTime.fromMillisecondsSinceEpoch(f.lastModified)
            : null,
      );

  VideoFile _toVideoFile(NetworkFile f) => VideoFile(
        path: f.path,
        name: f.name,
        size: f.size,
        dateModified: f.lastModified > 0
            ? DateTime.fromMillisecondsSinceEpoch(f.lastModified)
            : null,
        source: VideoSource.network,
        remotePath: f.path,
        connectionId: widget.connection.id,
      );

  Widget _message({
    required IconData icon,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: scheme.outline),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(Icons.refresh),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

/// 非视频文件条目：只读展示（不可点击播放），保证目录不因过滤而空白。
class _OtherFileTile extends StatelessWidget {
  final NetworkFile file;

  const _OtherFileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.insert_drive_file_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        file.size >= 0 ? formatFileSize(file.size) : '文件',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }
}