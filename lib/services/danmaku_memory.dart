/// 弹幕手动导入记忆存储：按视频路径记忆最近一次手动选择的弹幕文件，
/// 重启播放器/重启软件后自动恢复加载，无需重新选择（工作.md 弹幕阶段1
/// 用户反馈：手动导入的弹幕不被记忆）。
///
/// - 存储：SharedPreferences 单键 JSON（`{视频路径: 弹幕文件路径}`），
///   进程内缓存避免每次读取反序列化；
/// - 优先级：记忆的手动导入 **优先于** 同名自动查找（用户显式选择不被
///   覆盖，对齐字幕外挂记忆语义）；同名自动加载（9 种命名规则）的结果
///   不写入记忆（确定性查找，无需记忆）；
/// - 失效处理：记忆的弹幕文件被删除/不可读时由调用方清除该条记忆并
///   回落同名查找。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DanmakuManualMemory {
  DanmakuManualMemory();

  static const _key = 'danmaku_manual_memory';

  Map<String, String>? _cache;

  /// 读取全量映射（进程内缓存；首次读 SharedPreferences）
  Future<Map<String, String>> _map() async {
    final cached = _cache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    _cache = _decode(prefs.getString(_key));
    return _cache!;
  }

  /// 防御性解码：损坏数据 / 非字符串值一律丢弃，不抛异常
  Map<String, String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
    } catch (_) {
      // 损坏的 JSON 视为无记忆
    }
    return {};
  }

  /// 该视频记忆的手动弹幕文件路径（无记忆返回 null）
  Future<String?> get(String videoPath) async => (await _map())[videoPath];

  /// 记录/覆盖该视频的手动弹幕文件
  Future<void> set(String videoPath, String danmakuPath) async {
    final map = await _map();
    map[videoPath] = danmakuPath;
    await _persist(map);
  }

  /// 清除该视频的记忆（记忆的弹幕文件失效场景）
  Future<void> remove(String videoPath) async {
    final map = await _map();
    if (!map.containsKey(videoPath)) return;
    map.remove(videoPath);
    await _persist(map);
  }

  Future<void> _persist(Map<String, String> map) async {
    _cache = map;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }
}
