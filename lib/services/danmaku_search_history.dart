/// 网络弹幕搜索历史存储（工作.md 第 4 点）：记录用户搜索过的关键词，
/// 供搜索页以胶囊样式展示；支持一键清除、去重、上限与自动淘汰最旧关键词。
///
/// 纯数据层（无 UI），SharedPreferences 单键 JSON 持久化。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DanmakuSearchHistory {
  DanmakuSearchHistory({this.maxEntries = 10});

  static const _key = 'danmaku_search_history';

  /// 历史上限（默认 10 条；超出自动删除最旧）
  final int maxEntries;

  List<String>? _cache;

  Future<List<String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    _cache = _decode(prefs.getString(_key));
    return _cache!;
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final e in decoded) if (e is String) e];
      }
    } catch (_) {
      // 损坏数据视为无历史
    }
    return [];
  }

  /// 当前历史（新→旧）
  Future<List<String>> load() async => List.unmodifiable(await _load());

  /// 记录一次搜索：去重（已存在则提到最前）+ 超出上限删除最旧。
  Future<void> add(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final list = await _load();
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > maxEntries) {
      list.removeRange(maxEntries, list.length);
    }
    await _persist(list);
  }

  /// 一键清除全部历史。
  Future<void> clear() async {
    await _persist([]);
  }

  Future<void> _persist(List<String> list) async {
    _cache = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }
}
