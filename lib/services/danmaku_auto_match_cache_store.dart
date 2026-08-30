/// 弹幕自动匹配缓存存储（切集自动匹配弹幕，工作.md 第 7 点）：
/// 把用户选中的「番剧 + 完整集列表」持久化，切集时据此自动匹配并拉取弹幕。
///
/// SharedPreferences 单键 JSON 持久化；损坏数据防御性回退 null。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:moumou/models/danmaku_auto_match_cache.dart';

class DanmakuAutoMatchCacheStore {
  DanmakuAutoMatchCacheStore();

  static const _key = 'danmaku_auto_match_cache';

  DanmakuAutoMatchCache? _cache;
  bool _loaded = false;

  /// 读取缓存（进程内缓存；首次读 SharedPreferences）。
  Future<DanmakuAutoMatchCache?> load() async {
    if (_loaded) return _cache;
    final prefs = await SharedPreferences.getInstance();
    _cache = _decode(prefs.getString(_key));
    _loaded = true;
    return _cache;
  }

  /// 保存缓存（覆盖旧值）。
  Future<void> save(DanmakuAutoMatchCache cache) async {
    _cache = cache;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cache.toJson()));
  }

  /// 清空缓存。
  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  DanmakuAutoMatchCache? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return DanmakuAutoMatchCache.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // 损坏数据视为无缓存
    }
    return null;
  }
}
