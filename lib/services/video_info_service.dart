import 'package:flutter/services.dart';

/// 视频信息：时长 + 缩略图路径
class VideoInfo {
  final int durationMs;
  final String? thumbPath;

  const VideoInfo({required this.durationMs, this.thumbPath});
}

/// 通过原生 MediaMetadataRetriever 获取视频信息
class VideoInfoService {
  static const _channel = MethodChannel('moumou/video_info');

  static Future<VideoInfo> get(String path) async {
    final result = await _channel
        .invokeMapMethod<String, dynamic>('getVideoInfo', {'path': path});
    return VideoInfo(
      durationMs: (result?['durationMs'] as num?)?.toInt() ?? 0,
      thumbPath: result?['thumbPath'] as String?,
    );
  }
}
