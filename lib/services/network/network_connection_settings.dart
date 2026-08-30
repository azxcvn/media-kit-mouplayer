/// 网络存储连接（账号）配置清单：单例 ChangeNotifier + SharedPreferences 持久化，
/// 与现有 MediaScanSettings 等配置服务保持同构。
///
/// 说明：凭据当前以明文 JSON 存入 SharedPreferences（对齐本项目其余本地偏好），
/// 未引入加密以免在缺少 Android Keystore 绑定的情况下做成「假加密」。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:moumou/models/network_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkConnectionSettings extends ChangeNotifier {
  NetworkConnectionSettings._();

  static final NetworkConnectionSettings instance = NetworkConnectionSettings._();

  static const _key = 'network_connections';

  Future<void>? _loadFuture;
  List<NetworkConnection> _connections = [];
  int _nextId = 1;

  /// 只读连接列表（不含可变视图）。
  List<NetworkConnection> get connections => List.unmodifiable(_connections);

  NetworkConnection? byId(int id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> ensureLoaded() => _loadFuture ??= load();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final list = <NetworkConnection>[];
    var maxId = 0;
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is! Map) continue;
        final connection =
            NetworkConnection.fromJson(Map<String, dynamic>.from(decoded));
        list.add(connection);
        if (connection.id > maxId) maxId = connection.id;
      } catch (_) {
        // 单条损坏不拖垮整个列表。
      }
    }
    _connections = list;
    _nextId = maxId + 1;
    notifyListeners();
  }

  /// 新增一条连接，返回分配好 id 的完整对象。
  Future<NetworkConnection> add(NetworkConnection connection) async {
    await ensureLoaded();
    final withId = connection.copyWith(id: _nextId++);
    _connections = [..._connections, withId];
    notifyListeners();
    await _save();
    return withId;
  }

  Future<void> update(NetworkConnection connection) async {
    await ensureLoaded();
    _connections = [
      for (final e in _connections)
        if (e.id == connection.id) connection else e,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> remove(int id) async {
    await ensureLoaded();
    _connections = _connections.where((e) => e.id != id).toList();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _connections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  /// 测试用：重置状态。
  @visibleForTesting
  void reset() {
    _loadFuture = null;
    _connections = [];
    _nextId = 1;
    notifyListeners();
  }
}