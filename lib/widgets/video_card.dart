import 'dart:io';

import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/video_info_service.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/formatters.dart';

/// 视频卡片：缩略图 + 名称 + 字段（列表视图与目录详情页共用）
class VideoCard extends StatefulWidget {
  final VideoFile video;
  final Set<VideoField> fields;
  final VoidCallback onTap;

  const VideoCard({
    super.key,
    required this.video,
    required this.fields,
    required this.onTap,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final info = await VideoInfoService.get(widget.video.path);
    if (!mounted) return;
    setState(() {
      _thumbPath = info.thumbPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = widget.fields;
    // 同步读取最新进度（列表重建时自动刷新）
    final progress =
        PlaybackProgressService.instance.getProgress(widget.video.path);

    // 缩略图上的标签
    final sizeText = fields.contains(VideoField.size)
        ? formatFileSize(widget.video.size)
        : null;
    final durationText =
        fields.contains(VideoField.duration) && widget.video.durationMs > 0
        ? formatDuration(widget.video.durationMs)
        : null;

    // 右侧字段
    final rightTags = <Widget>[];
    if (fields.contains(VideoField.date)) {
      rightTags.add(
        _tag(
          scheme,
          Icons.calendar_today_outlined,
          formatDate(widget.video.dateModified),
        ),
      );
    }
    if (fields.contains(VideoField.resolution) &&
        widget.video.width > 0 &&
        widget.video.height > 0) {
      rightTags.add(
        _tag(
          scheme,
          Icons.aspect_ratio,
          '${widget.video.width}x${widget.video.height}',
        ),
      );
    }

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 缩略图（叠加字段标签 + 进度条）
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _thumbPath != null
                          ? Image.file(File(_thumbPath!), fit: BoxFit.cover)
                          : Container(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.movie_outlined,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                      if (sizeText != null && sizeText.isNotEmpty)
                        Positioned(
                          left: 4,
                          bottom: 6,
                          child: _thumbLabel(sizeText),
                        ),
                      if (durationText != null)
                        Positioned(
                          right: 4,
                          bottom: 6,
                          child: _thumbLabel(durationText),
                        ),
                      if (progress != null && widget.video.durationMs > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildProgressBar(scheme, progress),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                    if (rightTags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: rightTags),
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

  Widget _buildProgressBar(ColorScheme scheme, Duration progress) {
    final ratio = (progress.inMilliseconds / widget.video.durationMs).clamp(
      0.0,
      1.0,
    );
    return Container(
      height: 3,
      color: Colors.black.withValues(alpha: 0.4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio,
          child: Container(color: scheme.primary),
        ),
      ),
    );
  }

  Widget _thumbLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _tag(ColorScheme scheme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
