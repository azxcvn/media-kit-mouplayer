import 'package:flutter/services.dart';
import 'package:moumou/services/device_services.dart';

/// 缓存类别（key 与原生 `getCacheSizes` / `clearCache` 对应；纯数据，无 UI 依赖）
class CacheCategory {
  final String key;
  final String label;

  const CacheCategory(this.key, this.label);
}

/// 缓存管理服务：查询/清除各类应用缓存。
///
/// 原生实现见 `MainActivity.kt`（`cacheDir/thumbs/` 按文件名下划线分段区分
/// 进度条缩略图与列表封面；未来类别如弹幕/字幕预留 `other`）。
class CacheManagerService {
  CacheManagerService._();

  static const MethodChannel _channel = MethodChannel('moumou/video_info');

  /// 进度条视频缩略图缓存
  static const scrubThumbs = CacheCategory('scrubThumbs', '进度条视频缩略图');

  /// 视频列表封面缩略图缓存
  static const listThumbs = CacheCategory('listThumbs', '视频列表封面缩略图');

  /// 其他缓存（未来：弹幕文件 / 字幕文件等）
  static const other = CacheCategory('other', '其他缓存');

  /// 全部类别（顺序即展示顺序）
  static const all = [scrubThumbs, listThumbs, other];

  /// 各缓存类别占用字节数（失败返回空 map）
  static Future<Map<String, int>> getCacheSizes() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object>('getCacheSizes');
      if (raw == null) return const {};
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  /// 清除单个类别缓存（进度条缩略图同时清掉 Dart 内存缓存）
  static Future<bool> clearCategory(CacheCategory category) async {
    try {
      await _channel.invokeMethod<void>('clearCache', {'category': category.key});
      if (category.key == scrubThumbs.key) {
        DeviceServices.clearFrameCache();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 一键清除所有缓存
  static Future<bool> clearAll() async {
    try {
      await _channel.invokeMethod<void>('clearAllCaches');
      DeviceServices.clearFrameCache();
      return true;
    } catch (_) {
      return false;
    }
  }
}
