import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/options_sheet.dart';
import 'package:moumou/widgets/video_card.dart';

/// 文件夹视频列表页：列表模式下点击文件夹进入，只显示该文件夹内的视频
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
  void _showVideoOptions() {
    showSortOptionsSheet(
      context,
      widget.viewSettings,
      hasFolders: false,
      hasVideos: true,
    );
  }

  Future<void> _openPlayer(VideoFile video) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: playerRouteName),
        builder: (_) => PlayerPage(path: video.path, title: video.name),
      ),
    );
    // 从播放页返回后主动刷新，进度条立即更新
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
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
      ]),
      builder: (context, _) {
        final videos = widget.viewSettings.sortVideos(widget.videos);
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
            );
          },
        );
      },
    );
  }
}

