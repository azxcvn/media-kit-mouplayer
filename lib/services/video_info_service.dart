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

  /// 内存缓存：避免列表滚动往返时重复跨进程调用
  static final Map<String, VideoInfo> _cache = {};

  static Future<VideoInfo> get(String path) async {
    final cached = _cache[path];
    if (cached != null) return cached;

    final result = await _channel
        .invokeMapMethod<String, dynamic>('getVideoInfo', {'path': path});
    final info = VideoInfo(
      durationMs: (result?['durationMs'] as num?)?.toInt() ?? 0,
      thumbPath: result?['thumbPath'] as String?,
    );
    _cache[path] = info;
    return info;
  }
}
