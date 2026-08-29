import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:moumou/services/fast_thumbnails.dart';
import 'package:path_provider/path_provider.dart';

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

  /// 读取当前网络类型（播放界面顶部信息行「数据类型」图标用，工作.md 阶段1 第 1 点）。
  /// 返回 'wifi' / 'cellular' / 'ethernet' / 'none'；失败/无网络返回 'none'。
  static Future<String> getNetworkType() async {
    try {
      final v = await _channel.invokeMethod<String>('getNetworkType');
      return v ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

  // ── 听视频后台播放（前台服务保活，工作.md 阶段1 第 2 点）────

  /// 启动后台播放前台服务：保活进程，使音频在退到后台后继续播放（像音乐播放器）。
  /// [title] 为通知标题（当前曲目名）。进入听视频界面时调用。
  static Future<void> startBackgroundPlayback({String title = ''}) async {
    try {
      await _channel.invokeMethod<void>(
        'startBackgroundPlayback',
        {'title': title},
      );
    } catch (_) {
      // 非 Android / 服务不可用时静默忽略（退后台可能暂停，不影响前台使用）
    }
  }

  /// 停止后台播放前台服务。退出听视频界面时调用。
  static Future<void> stopBackgroundPlayback() async {
    try {
      await _channel.invokeMethod<void>('stopBackgroundPlayback');
    } catch (_) {
      // 静默忽略
    }
  }

  // ── 字幕功能（工作.md 阶段1 第 3 点）──────────────────

  /// 当前 Android SDK 版本（外挂字幕按版本选文件选择器：≤11 系统选择器，>11 自建）
  static Future<int> getSdkInt() async {
    try {
      final v = await _channel.invokeMethod<int>('getSdkInt');
      return v ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 列举目录内容（自建文件选择器用）；**目录不存在 / 不可读返回 null**
  /// （区别于真实存在的空目录，供选择器识别死路径并向上回退），
  /// 成功返回条目列表（可能为空）。异常返回 null。
  static Future<List<SubtitleDirEntry>?> listDirectory(String path) async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>(
        'listDirectory',
        {'path': path},
      );
      if (list == null) return null;
      return [
        for (final item in list)
          if (item is Map)
            SubtitleDirEntry(
              name: (item['name'] as String?) ?? '',
              path: (item['path'] as String?) ?? '',
              isDirectory: (item['isDirectory'] as bool?) ?? false,
              size: ((item['size'] as num?) ?? 0).toInt(),
              modifiedMs: ((item['modifiedMs'] as num?) ?? 0).toInt(),
            ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 系统字体列表（字幕字体设置用）；失败返回空列表。
  static Future<List<String>> getSystemFonts() async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('getSystemFonts');
      if (list == null) return const [];
      return [for (final f in list) if (f is String) f];
    } catch (_) {
      return const [];
    }
  }

  /// 把 content:// 字幕 uri 拷贝为应用内真实路径（libmpv 无法直接读 content://）；
  /// 返回真实绝对路径，失败返回 null。
  static Future<String?> copySubtitleFromUri(String uri, String name) async {
    try {
      return await _channel.invokeMethod<String>(
        'copySubtitleFromUri',
        {'uri': uri, 'name': name},
      );
    } catch (_) {
      return null;
    }
  }

  /// 把 content:// 弹幕 uri 拷贝为应用内真实路径（弹幕 XML 解析走 dart:io，
  /// 无法直接读 content://）；返回真实绝对路径，失败返回 null。
  static Future<String?> copyDanmakuFromUri(String uri, String name) async {
    try {
      return await _channel.invokeMethod<String>(
        'copyDanmakuFromUri',
        {'uri': uri, 'name': name},
      );
    } catch (_) {
      return null;
    }
  }

  /// 打开系统文件选择器（ACTION_OPEN_DOCUMENT）：返回所选 content:// uri；
  /// 用户取消/不可用返回 null。
  static Future<String?> openDocumentPicker() async {
    try {
      return await _channel.invokeMethod<String>('openDocumentPicker');
    } catch (_) {
      return null;
    }
  }

  /// 打开「音频」系统文件选择器（MIME 含 audio/*，.mp3/.m4a 等不再置灰）。
  static Future<String?> openAudioPicker() async {
    try {
      return await _channel.invokeMethod<String>('openAudioPicker');
    } catch (_) {
      return null;
    }
  }

  /// 把 content:// 音轨 uri 拷贝为应用内真实路径（libmpv 无法直接读 content://）；
  /// 返回真实绝对路径，失败返回 null。
  static Future<String?> copyAudioFromUri(String uri, String name) async {
    try {
      return await _channel.invokeMethod<String>(
        'copyAudioFromUri',
        {'uri': uri, 'name': name},
      );
    } catch (_) {
      return null;
    }
  }

  /// 打开「字体」系统文件选择器：MIME 含 font/*（.ttf/.otf 不再置灰）。
  static Future<String?> openFontPicker() async {
    try {
      return await _channel.invokeMethod<String>('openFontPicker');
    } catch (_) {
      return null;
    }
  }

  /// 把字体 content:// uri 拷贝到应用私有 fonts/ 目录（libass 需真实路径），
  /// 返回真实绝对路径，失败返回 null。
  static Future<String?> copyFontFromUri(String uri, String name) async {
    try {
      return await _channel.invokeMethod<String>(
        'copyFontFromUri',
        {'uri': uri, 'name': name},
      );
    } catch (_) {
      return null;
    }
  }

  /// 读取字体文件内部家族名（libass 的 sub-font 按家族名匹配，非文件名）。
  /// 失败返回空串。
  static Future<String> getFontFamilyName(String path) async {
    try {
      return await _channel.invokeMethod<String>('getFontFamilyName', {
        'path': path,
      }) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 获取应用内部字体目录路径
  static Future<String> getFontsDirectory() async {
    try {
      final dir = await _channel.invokeMethod<String>('getFontsDirectory');
      if (dir != null && dir.isNotEmpty) return dir;
    } catch (_) {}
    try {
      final appDir = await getApplicationSupportDirectory();
      final fontDir = Directory('${appDir.path}/fonts');
      if (!await fontDir.exists()) {
        await fontDir.create(recursive: true);
      }
      return fontDir.path;
    } catch (_) {
      return '';
    }
  }

  /// 确保应用内部字体目录可用（路线 C：直通系统字库 /system/fonts）
  static Future<String> ensureDefaultFontCopied() async => '';

  /// 打开系统目录选择器（ACTION_OPEN_DOCUMENT_TREE）：返回所选目录 tree uri；
  /// 用户取消/不可用返回 null。
  static Future<String?> openFontDirectoryPicker() async {
    try {
      return await _channel.invokeMethod<String>('openFontDirectoryPicker');
    } catch (_) {
      return null;
    }
  }

  /// 把用户选中目录里所有 .ttf/.otf/.ttc/.otc 字体一次性拷贝到应用私有
  /// fonts/ 目录，返回成功拷贝的文件数（失败返回 0）。
  static Future<int> copyFontsFromDirectory(String uri) async {
    try {
      final n = await _channel.invokeMethod<int>(
        'copyFontsFromDirectory',
        {'uri': uri},
      );
      return n ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 列出应用私有 fonts/ 目录内可用的字体（族名 + 文件名，按族名去重排序）。
  static Future<List<SubtitleFontEntry>> listFontEntries() async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('listFontEntries');
      if (list == null) return const [];
      return [
        for (final item in list)
          if (item is Map)
            SubtitleFontEntry(
              family: (item['family'] as String?) ?? '',
              file: (item['file'] as String?) ?? '',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 清空应用私有 fonts/ 目录（清除已导入的字体文件）。
  static Future<void> clearFontsDirectory() async {
    try {
      await _channel.invokeMethod<void>('clearFontsDirectory');
    } catch (_) {}
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

    // 失败冷却：同 key 近期真实解码失败（非被顶掉）→ 直接返回 null，
    // 避免同一失败位置被反复拖动反复重解（对齐 mpvRx 10s 冷却）。
    final lastFail = _frameFailAt[key];
    if (lastFail != null &&
        DateTime.now().millisecondsSinceEpoch - lastFail < _frameFailCooldownMs) {
      return null;
    }

    final future = _fetchFrame(path, bucketMs, maxWidth).then((result) {
      if (result.frame != null) {
        _frameCache[key] = result.frame!;
        _frameCacheBytes += result.frame!.rgba.lengthInBytes;
        _trimCache();
        _frameFailAt.remove(key);
      } else if (!result.stale) {
        // 真实解码失败（引擎不可用 / 解码失败）→ 记冷却时间戳
        _frameFailAt[key] = DateTime.now().millisecondsSinceEpoch;
      }
      return result.frame;
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
    int maxGapMs = 3000,
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
    _frameFailAt.clear();
  }

  /// 抓帧实现：FFmpeg 快速引擎（独立 isolate 解码，RGBA 直出，无编码往返）。
  /// 引擎不可用（内核未替换/非 Android）/失败/被新请求顶掉 → frame null。
  /// [GrabOutcome.stale] 区分「被顶掉」与「真实失败」。
  static Future<GrabOutcome> _fetchFrame(
    String path,
    int timeMs,
    int maxWidth,
  ) async {
    final sw = Stopwatch()..start();
    final result = await FastThumbnails.grab(
      path,
      timeMs / 1000.0,
      dimension: maxWidth.clamp(64, 4096),
      useHwdec: true,
    );
    sw.stop();
    final frame = result.frame;
    if (frame != null) {
      debugPrint('[Thumb] fast OK ${frame.rgba.lengthInBytes}B '
          '${frame.width}x${frame.height} ${sw.elapsedMilliseconds}ms');
    } else {
      debugPrint('[Thumb] fast ${result.stale ? 'stale' : 'null'} '
          '${sw.elapsedMilliseconds}ms');
    }
    return result;
  }

  /// Dart 侧缩略图 LRU（约 32 MB，按 RGBA 字节计，对齐 mpvRx 32MB LruCache）
  /// LinkedHashMap 按插入序维护：新帧插尾部，命中时 remove+put 移到尾部，
  /// 淘汰时删头部（最久未用，risk_audit #7 修复——原先按「最早插入」删，
  /// 快速来回拖动时可能淘汰掉马上要用的帧）。
  static const int _frameCacheMaxBytes = 32 * 1024 * 1024;
  static final Map<String, FastThumbFrame> _frameCache = {};
  static final Map<String, Future<FastThumbFrame?>> _inflight = {};

  /// 失败冷却（毫秒）：同 key 真实解码失败后，此窗口内不再重发引擎请求。
  static const int _frameFailCooldownMs = 10 * 1000;

  /// 真实解码失败时间戳（epoch ms）：被顶掉（stale）不计入。
  static final Map<String, int> _frameFailAt = {};
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

/// 目录条目（自建字幕文件选择器用，工作.md 阶段1 第 3 点）
class SubtitleDirEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final int modifiedMs;

  const SubtitleDirEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedMs,
  });
}

/// 已导入的自定义字体条目（字幕字体选择列表用，工作.md 第 1 点）。
class SubtitleFontEntry {
  /// libass `sub-font` 匹配用的家族名（truetypeparser 解析，非文件名）。
  final String family;

  /// 私有 fonts/ 目录内的字体文件名（展示用）。
  final String file;

  const SubtitleFontEntry({required this.family, required this.file});
}
