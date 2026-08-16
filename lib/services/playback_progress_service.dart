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

  /// 同步读取进度（调用前需先 load）
  Duration? getProgress(String path) {
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

  /// 保存进度并通知监听者
  Future<void> save(String path, Duration position) async {
    _cache[path] = position.inMilliseconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_cache));
  }
}
