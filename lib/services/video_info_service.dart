import 'package:flutter/services.dart';

/// 视频信息：时长 + 缩略图路径
class VideoInfo {
  final int durationMs;
  final String? thumbPath;

  const VideoInfo({required this.durationMs, this.thumbPath});
}

/// 视频基本媒体元数据（来自 MediaInfoLib 快速解析，列表字段用）：
/// 帧率 + 内嵌字幕信息。
class VideoBasicMetadata {
  final double frameRate;
  final bool hasEmbeddedSubtitles;
  final String subtitleCodec;

  const VideoBasicMetadata({
    this.frameRate = 0,
    this.hasEmbeddedSubtitles = false,
    this.subtitleCodec = '',
  });

  bool get hasAnyInfo => frameRate > 0 || hasEmbeddedSubtitles;
}

/// 通过原生 MediaMetadataRetriever / MediaInfoLib 获取视频信息
class VideoInfoService {
  static const _channel = MethodChannel('moumou/video_info');

  /// 内存缓存：避免列表滚动往返时重复跨进程调用
  static final Map<String, VideoInfo> _cache = {};

  /// 基本元数据内存缓存（帧率 / 字幕）
  static final Map<String, VideoBasicMetadata> _metaCache = {};

  /// 在飞去重：同 path 的并发请求共享同一个 Future（列表首屏几十张卡片
  /// 同时发起时只发一次跨进程调用，见 risk_audit #5）
  static final Map<String, Future<VideoInfo>> _inflight = {};

  /// 基本元数据在飞去重（同上）
  static final Map<String, Future<VideoBasicMetadata>> _metaInflight = {};

  static Future<VideoInfo> get(String path) async {
    final cached = _cache[path];
    if (cached != null) return cached;
    final inflight = _inflight[path];
    if (inflight != null) return inflight;

    final future = _fetchInfo(path);
    _inflight[path] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(path);
    }
  }

  static Future<VideoInfo> _fetchInfo(String path) async {
    final result = await _channel
        .invokeMapMethod<String, dynamic>('getVideoInfo', {'path': path});
    final info = VideoInfo(
      durationMs: (result?['durationMs'] as num?)?.toInt() ?? 0,
      thumbPath: result?['thumbPath'] as String?,
    );
    _cache[path] = info;
    return info;
  }

  /// 获取视频基本媒体元数据（帧率 / 内嵌字幕，MediaInfoLib 快速解析 + 磁盘缓存）。
  /// 失败返回空元数据，调用方自行降级（不显示字段）。
  static Future<VideoBasicMetadata> getBasicMetadata(String path) async {
    final cached = _metaCache[path];
    if (cached != null) return cached;
    final inflight = _metaInflight[path];
    if (inflight != null) return inflight;

    final future = _fetchBasicMetadata(path);
    _metaInflight[path] = future;
    try {
      return await future;
    } finally {
      _metaInflight.remove(path);
    }
  }

  static Future<VideoBasicMetadata> _fetchBasicMetadata(String path) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getVideoBasicMetadata', {
        'path': path,
      });
      final meta = VideoBasicMetadata(
        frameRate: (result?['frameRate'] as num?)?.toDouble() ?? 0,
        hasEmbeddedSubtitles: result?['hasSubtitles'] as bool? ?? false,
        subtitleCodec: result?['subtitleCodec'] as String? ?? '',
      );
      _metaCache[path] = meta;
      return meta;
    } catch (_) {
      return const VideoBasicMetadata();
    }
  }

  /// 获取视频完整媒体信息（MediaInfoLib，用于媒体信息页）
  static Future<Map<String, dynamic>?> getMediaInfo(String path) async {
    try {
      return await _channel
          .invokeMapMethod<String, dynamic>('getMediaInfo', {'path': path});
    } catch (_) {
      return null;
    }
  }
}
