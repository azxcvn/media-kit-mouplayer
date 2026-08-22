import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_thumbnail_plus/video_thumbnail_plus.dart';

/// 设备能力服务：系统音量 / 窗口亮度 / 任意时刻视频抓帧（本地文件）/ 画中画（PiP）。
///
/// - 音量/亮度/画中画：走 [MethodChannel]（`moumou/video_info`，原生见 `MainActivity.kt`）；
/// - 抓帧：**原生通道为主**（磁盘缓存 + MediaMetadataRetriever SYNC→CLOSEST
///   各自独立容错 + 落盘），video_thumbnail_plus 包为兜底（带超时防挂死，
///   成功也落盘）。
///
/// 纯数据层（无 UI），所有方法失败时返回 null / false，调用方自行降级。
class DeviceServices {
  DeviceServices._();

  static const MethodChannel _channel = MethodChannel('moumou/video_info');

  // ── 画中画（PiP）──────────────────────────────────────

  /// 设备是否支持画中画（API 26+ 且系统具备该特性），失败返回 false
  static Future<bool> isPipSupported() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isPipSupported');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 进入画中画小窗；[aspectWidth]/[aspectHeight] 为约分后的整数宽高比
  /// （如 16/9，见 `utils/pip_aspect.dart` 的 [pipAspectRatio]）。
  /// 已在画中画时返回 true；不支持/失败返回 false。
  static Future<bool> enterPip({
    required int aspectWidth,
    required int aspectHeight,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'enterPip',
        {'aspectWidth': aspectWidth, 'aspectHeight': aspectHeight},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 设置「返回桌面/上滑手势时自动进入画中画」（仅 API 31+ 生效，
  /// 旧系统静默忽略）。播放页进入时置 true、退出时置 false。
  static Future<void> setAutoPipEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        'setAutoPipEnabled',
        {'enabled': enabled},
      );
    } catch (_) {
      // 旧系统/不支持时静默忽略
    }
  }

  /// 读取系统媒体音量，返回 0 – 100（百分比），失败返回 null
  static Future<double?> getSystemVolume() async {
    try {
      final v = await _channel.invokeMethod<double>('getSystemVolume');
      if (v == null) return null;
      return v.clamp(0.0, 100.0);
    } catch (_) {
      return null;
    }
  }

  /// 写入系统媒体音量（0 – 100），失败返回 false
  static Future<bool> setSystemVolume(double percent) async {
    try {
      await _channel.invokeMethod<void>(
        'setSystemVolume',
        {'volume': percent.clamp(0.0, 100.0)},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取当前有效亮度（窗口已设亮度优先，否则系统亮度），0 – 1，失败返回 null
  static Future<double?> getBrightness() async {
    try {
      final v = await _channel.invokeMethod<double>('getBrightness');
      if (v == null || v < 0) return null;
      return v.clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  /// 设置窗口亮度（0 – 1）；传 null 恢复系统默认（-1）。
  /// 失败返回 false（如无窗口亮度权限的环境）。
  static Future<bool> setWindowBrightness(double? value) async {
    try {
      await _channel.invokeMethod<void>(
        'setWindowBrightness',
        {'brightness': value ?? -1.0},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取当前电池电量百分比（0 – 100，播放界面顶部信息行用）；
  /// 失败/不支持返回 null（调用方隐藏电量显示）。
  static Future<int?> getBatteryLevel() async {
    try {
      final v = await _channel.invokeMethod<int>('getBatteryLevel');
      if (v == null || v < 0) return null;
      return v.clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// 提取本地视频 [path] 在 [timeMs] 时刻的画面（JPEG 字节，最长边约 [maxWidth]）。
  ///
  /// 按秒分桶 + 原生/包内缓存；Dart 侧做一层 LRU 与在飞去重。
  static Future<Uint8List?> getVideoFrameAt(
    String path,
    int timeMs, {
    int maxWidth = 320,
  }) async {
    if (timeMs < 0) return null;
    // 按秒分桶，命中原生缓存
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final key = '$path|$bucketMs|$maxWidth';
    final cached = _frameCache[key];
    if (cached != null) {
      // LRU（risk_audit #7）：读取时移到尾部 = 最近使用，淘汰时删头部最久未用
      _frameCache
        ..remove(key)
        ..[key] = cached;
      return cached;
    }
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final future = _fetchFrame(path, bucketMs, maxWidth).then((bytes) {
      if (bytes != null && bytes.isNotEmpty) {
        _frameCache[key] = bytes;
        _frameCacheBytes += bytes.lengthInBytes;
        _trimCache();
      }
      return bytes;
    });
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  /// 内存缓存中查找精确秒桶的已生成帧（不触发任何解码）
  static Uint8List? peekFrame(
    String path,
    int timeMs, {
    int maxWidth = 320,
  }) {
    if (timeMs < 0) return null;
    final bucketMs = (timeMs ~/ 1000) * 1000;
    return _frameCache['$path|$bucketMs|$maxWidth'];
  }

  /// 内存缓存中查找与 [timeMs] 最近且间隔不超过 [maxGapMs] 的已生成帧。
  /// 快速拖动时先显示最近帧（秒显），精确帧异步补齐。
  static ({Uint8List bytes, int bucketMs})? peekNearestFrame(
    String path,
    int timeMs, {
    int maxWidth = 320,
    int maxGapMs = 10000,
  }) {
    if (timeMs < 0) return null;
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final prefix = '$path|';
    final suffix = '|$maxWidth';
    ({Uint8List bytes, int bucketMs})? best;
    var bestGap = maxGapMs + 1;
    for (final entry in _frameCache.entries) {
      if (!entry.key.startsWith(prefix) || !entry.key.endsWith(suffix)) {
        continue;
      }
      final b = int.tryParse(
        entry.key.substring(prefix.length, entry.key.length - suffix.length),
      );
      if (b == null) continue;
      final gap = (b - bucketMs).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = (bytes: entry.value, bucketMs: b);
      }
    }
    return best;
  }

  /// 测试用：向内存缓存注入一帧（模拟预生成/已解码）
  @visibleForTesting
  static void debugPutFrame(String path, int timeMs, Uint8List bytes) {
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final key = '$path|$bucketMs|320';
    _frameCache[key] = bytes;
    _frameCacheBytes += bytes.lengthInBytes;
    _trimCache();
  }

  /// 测试用：清空内存缓存
  @visibleForTesting
  static void debugClearFrames() {
    _frameCache.clear();
    _frameCacheBytes = 0;
    _inflight.clear();
  }

  /// 抓帧实现（**原生通道为主**，包为兜底）：
  ///
  /// 1. 原生 `getVideoFrameAt`：磁盘缓存命中 → 零解码；未命中走
  ///    `MediaMetadataRetriever`（SYNC 快 → CLOSEST 稳，各自独立容错），
  ///    成功后落盘——保证磁盘缓存始终有数据、重开视频零解码；
  /// 2. 包（video_thumbnail_plus，只走 SYNC）作为兜底，**带 4 秒超时**
  ///    防止插件挂死导致永久转圈；成功时同样落盘（`putVideoFrame`）。
  ///
  /// 任一路径失败都不抛异常（返回 null），由调用方显示加载占位。
  static Future<Uint8List?> _fetchFrame(
    String path,
    int timeMs,
    int maxWidth,
  ) async {
    // 诊断日志：定位「原生路径失败 / 写盘未发生」的根因
    debugPrint('[Thumb] _fetchFrame path=$path t=$timeMs w=$maxWidth');
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getVideoFrameAt',
        {'path': path, 'timeMs': timeMs, 'maxWidth': maxWidth},
      );
      if (bytes != null && bytes.isNotEmpty) {
        debugPrint('[Thumb] native OK ${bytes.length}B');
        return bytes;
      }
      debugPrint('[Thumb] native null/empty');
    } catch (e) {
      debugPrint('[Thumb] native ERROR $e');
    }
    try {
      final bytes = await VideoThumbnailPlus.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: 60,
        timeMs: timeMs,
      ).timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (bytes != null && bytes.isNotEmpty) {
        debugPrint('[Thumb] package OK ${bytes.length}B');
        // 包成功的帧也写入磁盘缓存（异步，不阻塞），下次零解码
        unawaited(
          _channel.invokeMethod<void>(
            'putVideoFrame',
            {'path': path, 'timeMs': timeMs, 'maxWidth': maxWidth, 'bytes': bytes},
          ).catchError((e) => debugPrint('[Thumb] putVideoFrame ERROR $e')),
        );
        return bytes;
      }
      debugPrint('[Thumb] package null/empty');
    } catch (e) {
      debugPrint('[Thumb] package ERROR $e');
    }
    return null;
  }

  /// Dart 侧缩略图 LRU（约 24 MB）
  /// LinkedHashMap 按插入序维护：新帧插尾部，命中时 remove+put 移到尾部，
  /// 淘汰时删头部（最久未用，risk_audit #7 修复——原先按「最早插入」删，
  /// 快速来回拖动时可能淘汰掉马上要用的帧）。
  static const int _frameCacheMaxBytes = 24 * 1024 * 1024;
  // Dart 的 Map 字面量即 LinkedHashMap（插入序）：新帧插尾部，命中时
  // remove+put 移到尾部，淘汰时删头部（最久未用）——见上方说明。
  static final Map<String, Uint8List> _frameCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static int _frameCacheBytes = 0;

  static void _trimCache() {
    while (_frameCacheBytes > _frameCacheMaxBytes &&
        _frameCache.isNotEmpty) {
      final key = _frameCache.keys.first;
      _frameCacheBytes -= _frameCache.remove(key)!.lengthInBytes;
    }
  }

  /// 清空缩略图缓存（切换视频 / 播放页销毁时调用）
  static void clearFrameCache() {
    _frameCache.clear();
    _frameCacheBytes = 0;
    _inflight.clear();
  }
}
