import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:moumou/services/fast_thumbnails.dart';

/// 设备能力服务：系统音量 / 窗口亮度 / 任意时刻视频抓帧（本地文件）/ 画中画（PiP）。
///
/// - 音量/亮度/电池/画中画：走 [MethodChannel]（`moumou/video_info`，原生见 `MainActivity.kt`）；
/// - 抓帧：**FFmpeg 快速引擎**（自建 libmpv.so 内核的 `mk_thumbnail_grab`，
///   独立解码实例 + MediaCodec 硬解，与播放内核完全并行，单帧 ~85ms）。
///   RGBA 直通内存缓存与 UI，无磁盘缓存、无旧链路降级。
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

  // ── 任意时刻抓帧（FFmpeg 快速引擎，RGBA 直通）────────

  /// 提取本地视频 [path] 在 [timeMs] 时刻的画面（RGBA 帧，最长边约 [maxWidth]）。
  ///
  /// 按秒分桶 + 内存 LRU + 在飞去重；引擎不可用或被新请求顶掉时返回 null，
  /// 由调用方显示占位或邻近帧（[peekNearestFrame]）。
  static Future<FastThumbFrame?> getVideoFrameAt(
    String path,
    int timeMs, {
    int maxWidth = 320,
  }) async {
    if (timeMs < 0) return null;
    // 按秒分桶
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final key = '$path|$bucketMs|$maxWidth';
    final cached = _frameCache[key];
    if (cached != null) {
      // LRU：读取时移到尾部 = 最近使用，淘汰时删头部最久未用
      _frameCache
        ..remove(key)
        ..[key] = cached;
      return cached;
    }
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final future = _fetchFrame(path, bucketMs, maxWidth).then((frame) {
      if (frame != null) {
        _frameCache[key] = frame;
        _frameCacheBytes += frame.rgba.lengthInBytes;
        _trimCache();
      }
      return frame;
    });
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  /// 内存缓存中查找精确秒桶的已生成帧（不触发任何解码）
  static FastThumbFrame? peekFrame(
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
  static ({FastThumbFrame frame, int bucketMs})? peekNearestFrame(
    String path,
    int timeMs, {
    int maxWidth = 320,
    int maxGapMs = 10000,
  }) {
    if (timeMs < 0) return null;
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final prefix = '$path|';
    final suffix = '|$maxWidth';
    ({FastThumbFrame frame, int bucketMs})? best;
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
        best = (frame: entry.value, bucketMs: b);
      }
    }
    return best;
  }

  /// 测试用：向内存缓存注入一帧（模拟预生成/已解码）
  @visibleForTesting
  static void debugPutFrame(String path, int timeMs, FastThumbFrame frame) {
    final bucketMs = (timeMs ~/ 1000) * 1000;
    final key = '$path|$bucketMs|320';
    _frameCache[key] = frame;
    _frameCacheBytes += frame.rgba.lengthInBytes;
    _trimCache();
  }

  /// 测试用：清空内存缓存
  @visibleForTesting
  static void debugClearFrames() {
    _frameCache.clear();
    _frameCacheBytes = 0;
    _inflight.clear();
  }

  /// 抓帧实现：FFmpeg 快速引擎（独立 isolate 解码，RGBA 直出，无编码往返）。
  /// 引擎不可用（内核未替换/非 Android）/失败/被新请求顶掉 → null。
  static Future<FastThumbFrame?> _fetchFrame(
    String path,
    int timeMs,
    int maxWidth,
  ) async {
    final sw = Stopwatch()..start();
    final frame = await FastThumbnails.grab(
      path,
      timeMs / 1000.0,
      dimension: maxWidth.clamp(64, 4096),
      useHwdec: true,
    );
    sw.stop();
    if (frame != null) {
      debugPrint('[Thumb] fast OK ${frame.rgba.lengthInBytes}B '
          '${frame.width}x${frame.height} ${sw.elapsedMilliseconds}ms');
    } else {
      debugPrint('[Thumb] fast null/stale ${sw.elapsedMilliseconds}ms');
    }
    return frame;
  }

  /// Dart 侧缩略图 LRU（约 24 MB，按 RGBA 字节计）
  /// LinkedHashMap 按插入序维护：新帧插尾部，命中时 remove+put 移到尾部，
  /// 淘汰时删头部（最久未用，risk_audit #7 修复——原先按「最早插入」删，
  /// 快速来回拖动时可能淘汰掉马上要用的帧）。
  static const int _frameCacheMaxBytes = 24 * 1024 * 1024;
  static final Map<String, FastThumbFrame> _frameCache = {};
  static final Map<String, Future<FastThumbFrame?>> _inflight = {};
  static int _frameCacheBytes = 0;

  static void _trimCache() {
    while (_frameCacheBytes > _frameCacheMaxBytes &&
        _frameCache.isNotEmpty) {
      final key = _frameCache.keys.first;
      _frameCacheBytes -= _frameCache.remove(key)!.rgba.lengthInBytes;
    }
  }

  /// 清空 Dart 内存缓存（「清除所有缓存」时调用）
  static void clearFrameCache() {
    debugClearFrames();
  }
}
