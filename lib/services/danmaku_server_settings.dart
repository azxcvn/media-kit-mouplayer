/// 弹幕服务器设置（工作.md 第 6/7 点）：全局单例 ChangeNotifier +
/// shared_preferences 持久化，管理：
/// - 弹幕服务器列表（内置弹弹Play 默认服务器 + 用户自建服务器，可增删/启停）；
/// - 「切集自动匹配弹幕」开关。
///
/// 启用的服务器同时用于网络弹幕搜索与自动匹配，搜索结果合并展示
/// （见 `services/danmaku_network_service.dart`）。
///
/// **互斥约束（工作.md 第 7 点，收尾阶段恢复）**：默认弹弹Play 服务器启用时
/// 不允许开启「切集自动匹配」。为避免 UI 与运行时各判一次而漂移，互斥统一
/// 由本服务裁决——[autoMatchEnabled] 是唯一生效值（默认服务器启用时恒 false），
/// [autoMatchAllowed] / [autoMatchBlockedReason] 供 UI 变灰与提示文案复用。
/// 用户原始偏好保留在 [autoMatchPreference]，停用默认服务器后自动恢复生效。
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

  /// 「切集自动匹配弹幕」**生效值**（UI 显示与运行时判定都用这个）。
  ///
  /// 与默认弹弹Play 服务器**互斥**（工作.md 第 7 点收尾恢复的限制）：默认
  /// 服务器启用时恒为 false，无论用户此前存过什么偏好。
  bool get autoMatchEnabled => _autoMatchEnabled && !isDefaultEnabled;

  /// 用户存下来的原始偏好（**不含互斥判定**，仅供设置页/测试观察）。
  ///
  /// 保留原始值的意义：用户停用默认服务器 → 开启自动匹配 → 又启用默认服务器
  /// 时，只是「暂时不生效」；再次停用默认服务器即恢复其选择，不静默丢偏好。
  bool get autoMatchPreference => _autoMatchEnabled;

  /// 当前是否允许开启「切集自动匹配」（默认服务器启用时不允许）
  bool get autoMatchAllowed => !isDefaultEnabled;

  /// 不允许开启时的**短**原因文案（副标题用）；允许时为 null。
  ///
  /// 副标题空间有限（窄屏两行就显挤），这里只给动作指引；完整解释见
  /// [autoMatchBlockedMessage]（点击时的 toast）。两句都放在服务层，
  /// 页面里不出现文案字面量，避免多处措辞漂移。
  String? get autoMatchBlockedReason =>
      autoMatchAllowed ? null : '请先停用弹弹Play 服务器';

  /// 不允许开启时的**完整**说明（toast 用）；允许时为 null。
  String? get autoMatchBlockedMessage => autoMatchAllowed
      ? null
      : '已启用「${DanmakuServer.defaultName}」服务器时不可开启'
          '「切集自动匹配弹幕」，如需使用请先停用该服务器';

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
  /// 限制（工作.md 第 7 点，收尾阶段恢复）：默认弹弹Play 服务器启用时
  /// **拒绝开启**，返回 false 供 UI 弹 toast；关闭永远允许。写偏好本身
  /// 不做互斥擦除——互斥在读取侧（[autoMatchEnabled]）生效，用户停用默认
  /// 服务器后其选择自动恢复。
  Future<bool> setAutoMatchEnabled(bool enabled) async {
    await ensureLoaded();
    if (enabled && !autoMatchAllowed) return false;
    if (_autoMatchEnabled == enabled) return true;
    _autoMatchEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoMatch, enabled);
    return true;
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
