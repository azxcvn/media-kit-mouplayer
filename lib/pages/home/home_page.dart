import 'package:flutter/material.dart';
import 'package:moumou/models/video_folder.dart';
import 'package:moumou/pages/home/folder_detail_page.dart';
import 'package:moumou/services/video_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// 首页：展示视频文件夹列表
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  List<VideoFolder> _folders = [];
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

    final status = await Permission.videos.request();
    if (!status.isGranted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }

    final folders = await VideoScanner.scanFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频库'),
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
        icon: Icons.video_library_outlined,
        message: '需要存储权限才能扫描视频',
        buttonText: '重新申请权限',
        onPressed: _load,
      );
    }
    if (_folders.isEmpty) {
      return _buildMessage(
        icon: Icons.folder_off_outlined,
        message: '没有找到视频文件夹',
        buttonText: '重新扫描',
        onPressed: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: _folders.length,
        itemBuilder: (context, index) {
          final folder = _folders[index];
          return _FolderCard(
            folder: folder,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FolderDetailPage(folder: folder),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
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
            icon: const Icon(Icons.refresh),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

/// 文件夹卡片
class _FolderCard extends StatelessWidget {
  final VideoFolder folder;
  final VoidCallback onTap;

  const _FolderCard({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${folder.videoCount} 个视频',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
