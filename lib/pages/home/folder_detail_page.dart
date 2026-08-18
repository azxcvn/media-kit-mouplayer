import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/media_info/media_info_page.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/options_sheet.dart';
import 'package:moumou/widgets/video_card.dart';

/// 文件夹视频列表页：列表模式下点击文件夹进入，只显示该文件夹内的视频。
/// 右上角从左到右：**搜索** → 排序与字段。
class FolderDetailPage extends StatefulWidget {
  final String title;
  final List<VideoFile> videos;
  final ViewSettings viewSettings;

  const FolderDetailPage({
    super.key,
    required this.title,
    required this.videos,
    required this.viewSettings,
  });

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showVideoOptions() {
    showSortOptionsSheet(
      context,
      widget.viewSettings,
      hasFolders: false,
      hasVideos: true,
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

  Future<void> _openPlayer(VideoFile video) async {
    // 传当前可见的排序列表，作为播放页「下一集」的兄弟列表
    final playlist = widget.viewSettings.sortVideos(widget.videos);
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
    // 从播放页返回后主动刷新，进度条立即更新
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
                  hintText: '搜索视频',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              )
            : Text(widget.title),
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
            tooltip: '排序与字段',
            onPressed: _showVideoOptions,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.videos.isEmpty) {
      return const Center(child: Text('该文件夹没有视频'));
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.viewSettings,
        PlaybackProgressService.instance,
        PlayerControlsSettings.instance,
      ]),
      builder: (context, _) {
        var videos = widget.viewSettings.sortVideos(widget.videos);
        if (_query.isNotEmpty) {
          videos = videos
              .where((v) => v.name.toLowerCase().contains(_query))
              .toList();
        }
        if (videos.isEmpty && _query.isNotEmpty) {
          return const Center(child: Text('没有匹配的视频'));
        }
        // 底部安全区已由全局 SafeArea 处理
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return VideoCard(
              video: video,
              fields: widget.viewSettings.videoFields,
              onTap: () => _openPlayer(video),
              onInfoTap: () => _openMediaInfo(video),
            );
          },
        );
      },
    );
  }
}
