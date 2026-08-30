/// 弹幕服务器设置（工作.md 第 6/7 点）：全局单例 ChangeNotifier +
/// shared_preferences 持久化，管理：
/// - 弹幕服务器列表（内置弹弹Play 默认服务器 + 用户自建服务器，可增删/启停）；
/// - 「切集自动匹配弹幕」开关。
///
/// 启用的服务器同时用于网络弹幕搜索与自动匹配，搜索结果合并展示
/// （见 `services/danmaku_network_service.dart`）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moumou/models/danmaku_server.dart';

class DanmakuServerSettings extends ChangeNotifier {
  static final DanmakuServerSettings instance = DanmakuServerSettings._();

  DanmakuServerSettings._();

  static const _keyServers = 'dandanplay_servers';
  static const _keyAutoMatch = 'danmaku_auto_match_enabled';

  /// 加载去重（risk_audit #9）：setter 在改设置前 await [ensureLoaded]。
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() => _loadFuture ??= load();

  List<DanmakuServer> _servers = [DanmakuServer.createDefault()];
  bool _autoMatchEnabled = false;

  /// 全部服务器（含默认）
  List<DanmakuServer> get servers => List.unmodifiable(_servers);

  /// 已启用的服务器（搜索 / 匹配用）
  List<DanmakuServer> get enabledServers =>
      _servers.where((s) => s.isEnabled).toList();

  /// 是否启用「切集自动匹配弹幕」
  bool get autoMatchEnabled => _autoMatchEnabled;

  /// 默认（弹弹Play）服务器当前是否启用
  bool get isDefaultEnabled =>
      _servers.any((s) => s.isDefault && s.isEnabled);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _servers = _decodeServers(prefs.getString(_keyServers));
    _autoMatchEnabled = prefs.getBool(_keyAutoMatch) ?? false;
    notifyListeners();
  }

  /// 防御性解码：损坏数据回退「仅默认服务器」，且始终兜底保留默认服务器。
  List<DanmakuServer> _decodeServers(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [DanmakuServer.createDefault()];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = <DanmakuServer>[];
        for (final item in decoded) {
          if (item is Map) {
            final s = DanmakuServer.fromJson(item.cast<String, dynamic>());
            if (s != null) list.add(s);
          }
        }
        if (list.every((s) => !s.isDefault)) {
          list.insert(0, DanmakuServer.createDefault());
        }
        return list;
      }
    } catch (_) {
      // 损坏数据回退默认
    }
    return [DanmakuServer.createDefault()];
  }

  Future<void> _persistServers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyServers,
      jsonEncode([for (final s in _servers) s.toJson()]),
    );
  }

  /// 添加自建服务器（名称 + 地址；地址统一去掉末尾 `/`）。
  Future<void> addServer(String name, String url) async {
    await ensureLoaded();
    final trimmedName = name.trim();
    var trimmedUrl = url.trim();
    while (trimmedUrl.endsWith('/')) {
      trimmedUrl = trimmedUrl.substring(0, trimmedUrl.length - 1);
    }
    if (trimmedName.isEmpty || trimmedUrl.isEmpty) return;
    _servers = [
      ..._servers,
      DanmakuServer(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: trimmedName,
        url: trimmedUrl,
        isEnabled: true,
        isDefault: false,
      ),
    ];
    notifyListeners();
    await _persistServers();
  }

  /// 删除服务器（默认服务器不可删除，忽略该请求）。
  Future<void> removeServer(String id) async {
    await ensureLoaded();
    final target = _servers.where((s) => s.id == id).firstOrNull;
    if (target == null || target.isDefault) return;
    _servers = _servers.where((s) => s.id != id).toList();
    notifyListeners();
    await _persistServers();
  }

  /// 切换服务器启停。
  Future<void> setServerEnabled(String id, bool enabled) async {
    await ensureLoaded();
    _servers = [
      for (final s in _servers)
        s.id == id ? s.copyWith(isEnabled: enabled) : s,
    ];
    notifyListeners();
    await _persistServers();
  }

  /// 设置「切集自动匹配弹幕」开关。
  ///
  /// 说明（工作.md 第 7 点）：开发阶段**故意解除**「启用弹弹Play 服务器时
  /// 禁止打开此开关」的写死限制，待弹弹Play 自动匹配联调通过、收尾阶段再
  /// 恢复该限制。
  Future<void> setAutoMatchEnabled(bool enabled) async {
    await ensureLoaded();
    if (_autoMatchEnabled == enabled) return;
    _autoMatchEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoMatch, enabled);
  }

  /// 测试用：恢复默认值并清加载标记（单例在测试间共享，避免状态泄漏）。
  @visibleForTesting
  void resetForTest() {
    _loadFuture = null;
    _servers = [DanmakuServer.createDefault()];
    _autoMatchEnabled = false;
    notifyListeners();
  }
}
