import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/app_dialog.dart';
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
    showAppDialog(
      context: context,
      builder: (context) =>
          _VideoOptionsSheet(viewSettings: widget.viewSettings),
    );
  }

  Future<void> _openPlayer(VideoFile video) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
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

/// 视频列表的排序与字段弹窗
class _VideoOptionsSheet extends StatelessWidget {
  final ViewSettings viewSettings;

  const _VideoOptionsSheet({required this.viewSettings});

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
                  Text('排序与字段', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _sectionTitle(context, '排序方式'),
                  SegmentedButton<VideoSortField>(
                    showSelectedIcon: false,
                    segments: VideoSortField.values
                        .map(
                          (e) => ButtonSegment(value: e, label: Text(e.label)),
                        )
                        .toList(),
                    selected: {viewSettings.videoSortField},
                    onSelectionChanged: (s) =>
                        viewSettings.setVideoSortField(s.first),
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
                    selected: {viewSettings.videoSortOrder},
                    onSelectionChanged: (s) =>
                        viewSettings.setVideoSortOrder(s.first),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  _sectionTitle(context, '显示字段'),
                  Align(
                    alignment: Alignment.center,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: VideoField.values.map((f) {
                        final selected = viewSettings.videoFields.contains(f);
                        return FilterChip(
                          label: Text(f.label),
                          selected: selected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) => viewSettings.toggleVideoField(f),
                        );
                      }).toList(),
                    ),
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
