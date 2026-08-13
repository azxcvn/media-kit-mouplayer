import 'dart:io';

import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/models/video_folder.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/video_info_service.dart';
import 'package:moumou/services/video_scanner.dart';

/// 文件夹详情页：列出该文件夹内的视频（卡片式 + 缩略图）
class FolderDetailPage extends StatefulWidget {
  final VideoFolder folder;

  const FolderDetailPage({super.key, required this.folder});

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  List<VideoFile> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = Directory(widget.folder.path);
    final videos = <VideoFile>[];

    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (VideoScanner.videoExt.any((ext) => lower.endsWith(ext))) {
          videos.add(VideoFile(
            path: entity.path,
            name: entity.path.split('/').last,
          ));
        }
      }
    }

    videos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _videos = videos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? const Center(child: Text('该文件夹没有视频'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return _VideoCard(
                      video: video,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerPage(
                              path: video.path,
                              title: video.name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

/// 视频卡片：缩略图 + 文件名 + 大小
class _VideoCard extends StatefulWidget {
  final VideoFile video;
  final VoidCallback onTap;

  const _VideoCard({required this.video, required this.onTap});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  String? _thumbPath;
  String? _sizeText;
  String? _durationText;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await VideoInfoService.get(widget.video.path);
    final file = File(widget.video.path);
    String? sizeText;
    if (await file.exists()) {
      sizeText = _formatSize(await file.length());
    }
    if (!mounted) return;
    setState(() {
      _thumbPath = info.thumbPath;
      _sizeText = sizeText;
      if (info.durationMs > 0) {
        _durationText = _formatDuration(info.durationMs);
      }
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: _thumbPath != null
                      ? Image.file(
                          File(_thumbPath!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_sizeText != null || _durationText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        [_durationText, _sizeText]
                            .whereType<String>()
                            .join(' · '),
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.play_circle_outline, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
