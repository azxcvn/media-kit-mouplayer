import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放进度服务：记录每个视频上次播放到的位置（可监听，进度变化自动通知）
class PlaybackProgressService extends ChangeNotifier {
  static const _key = 'playback_progress';
  static final PlaybackProgressService instance = PlaybackProgressService._();

  PlaybackProgressService._();

  Map<String, int> _cache = {};
  bool _loaded = false;
  Future<void>? _loadFuture;

  /// 写入串行链：保证多次 save 的 prefs 写入按调用顺序落盘，
  /// 避免异步写入乱序导致「最后一次保存」被旧快照覆盖
  /// （工作.md 第 9 点：快速退出/进入循环 + 重启后恢复百分比失效的根因之一）。
  Future<void> _writeChain = Future.value();

  /// 节流（risk_audit #3）：同一视频 [persistInterval] 内只落盘一次，
  /// 内存缓存照常每次更新——避免每次退出/切集都整表 jsonEncode + 全量写盘。
  /// 视频库几千条后单次序列化可达数 MB，节流后写盘频率降到可接受范围。
  static const Duration _persistInterval = Duration(seconds: 30);

  /// 每个 path 最近一次落盘时间（节流判定用）
  final Map<String, DateTime> _lastPersistedAt = {};

  /// 确保已从磁盘加载（首次 get/save 前调用；main.dart 的 load 为异步，
  /// 播放页可能在加载完成前就读进度——必须等待，否则读到空缓存不恢复）。
  Future<void> ensureLoaded() => _loadFuture ??= load();

  /// 同步读取进度（调用前需先 await [ensureLoaded]；未加载时返回 null）
  Duration? getProgress(String path) {
    if (!_loaded) return null;
    final ms = _cache[path];
    return ms != null ? Duration(milliseconds: ms) : null;
  }

  /// 启动时加载全部进度
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      _cache = Map<String, int>.from(jsonDecode(json) as Map);
    }
    notifyListeners();
  }

  /// 保存进度并通知监听者。
  ///
  /// 可靠性（工作.md 第 9 点）：
  /// - 先 await [ensureLoaded]，防止 load() 的 `_cache = ...` 覆盖掉
  ///   刚写入内存的新进度（重启后快速进出的竞态）；
  /// - 写入走 [_writeChain] 串行化，快照在调用时同步生成，
  ///   保证磁盘上的最终内容 = 最后一次调用时的完整缓存。
  ///
  /// 节流（risk_audit #3）：同一 path 在 [_persistInterval] 内重复保存
  /// 只更新内存，不重复整表写盘（用户连续退出/切集同一视频时收益最大；
  /// 退出/切集时内存进度仍是最新的，进程正常存活不受影响）。
  Future<void> save(String path, Duration position) async {
    await ensureLoaded();
    _cache[path] = position.inMilliseconds;
    notifyListeners();
    final last = _lastPersistedAt[path];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _persistInterval) {
      return; // 节流命中：内存已更新，跳过本轮全量写盘
    }
    _lastPersistedAt[path] = now;
    final snapshot = jsonEncode(_cache);
    _writeChain = _writeChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, snapshot);
    });
    await _writeChain;
  }
}
