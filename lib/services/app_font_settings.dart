import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show FontWeight;
import 'package:moumou/services/device_services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// App 全局字体设置（工作.md 第 3 点）：用户导入自定义字体后全局应用，
/// 关闭时跟随系统字体。
///
/// 与字幕字体（§4.10 libass）是两套机制：本服务走 Flutter 引擎
/// `dart:ui loadFontFromList` 注册 + Skia 渲染（ThemeData.fontFamily /
/// textTheme 字重 / MediaQuery 字号缩放），字幕走 libass。两者共享
/// filesDir/fonts/ 同一字体目录，但注册与引用方式完全不同。
///
/// 全局单例（同 [SubtitleSettings] 模式）：ChangeNotifier +
/// shared_preferences 持久化；main.dart 合并监听，改值即时全 App 生效。
class AppFontSettings extends ChangeNotifier {
  static final AppFontSettings instance = AppFontSettings._();

  AppFontSettings._();

  /// 加载去重（与其它设置单例同模式）
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyEnabled = 'app_font_enabled';
  static const _keyFamily = 'app_font_family';
  static const _keyFile = 'app_font_file';
  static const _keyTextScale = 'app_font_text_scale';
  static const _keyFontWeight = 'app_font_weight';

  /// 字号缩放范围（0.85x – 1.6x，默认 1.0；对齐 PiliPlus）
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.6;

  bool _enabled = false;
  String? _family;
  String? _file;
  double _textScale = 1.0;
  int _fontWeight = -1; // -1 = 默认（不覆盖）；0~8 = FontWeight.values 下标

  bool get enabled => _enabled;
  String? get family => _family;

  /// filesDir/fonts/ 内字体文件名（冷启动重读字节用）
  String? get file => _file;
  double get textScale => _textScale;
  int get fontWeightIndex => _fontWeight;

  /// 实际生效字体族名（null = 跟随系统默认字体）
  String? get effectiveFamily => (_enabled && _family != null) ? _family : null;

  /// 实际生效字重（null = 不覆盖，交给引擎默认；仅字体已启用且已选时生效）
  FontWeight? get effectiveFontWeight =>
      (_enabled && _family != null && _fontWeight >= 0)
          ? FontWeight.values[_fontWeight]
          : null;

  /// 实际生效字号缩放（字体未启用时 1.0 = 不缩放，也保持系统无障碍缩放）
  double get effectiveTextScale =>
      (_enabled && _family != null) ? _textScale : 1.0;

  /// 启动时从本地恢复
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _family = prefs.getString(_keyFamily);
    _file = prefs.getString(_keyFile);
    _textScale = (prefs.getDouble(_keyTextScale) ?? 1.0)
        .clamp(minTextScale, maxTextScale);
    _fontWeight = (prefs.getInt(_keyFontWeight) ?? -1).clamp(-1, 8);
    notifyListeners();
  }

  /// 冷启动：把已选字体重新注册进引擎（`loadFontFromList` 只对当前进程有效，
  /// 必须在首次渲染该 family 前注册）。文件丢失/损坏 → 静默回落默认并清持久化
  /// （对齐 PiliPlus 的「文件不存在即删配置」容错）。
  Future<void> registerCurrentFont() async {
    if (!_enabled || _family == null || _file == null) return;
    final ok = await registerFontFile(_family!, _file!);
    if (ok) return;
    _enabled = false;
    _family = null;
    _file = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
    await prefs.remove(_keyFamily);
    await prefs.remove(_keyFile);
  }

  /// 读 filesDir/fonts/`<file>` 字节并以 [family] 注册进 Flutter 引擎。
  /// App 全局字体与弹幕自定义字体共用（同一引擎字体集合，各按族名命中）。
  /// 失败返回 false（文件被删/损坏/非 Android）。
  static Future<bool> registerFontFile(String family, String file) async {
    try {
      final dir = await DeviceServices.getFontsDirectory();
      final bytes = await File(p.join(dir, file)).readAsBytes();
      await ui.loadFontFromList(bytes, fontFamily: family);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool v) async {
    await ensureLoaded();
    if (_enabled == v) return;
    // 启用时先把已选字体（重新）注册进引擎，再切换状态并通知：
    // 冷启动后（尤其上次处于关闭状态时重启）registerCurrentFont 会跳过注册，
    // 引擎字体集合里没有该 family；若只改开关不重新注册，重启后首次启用时
    // 字体不生效。先注册后通知也避免「状态已生效但引擎未注册」的首帧回落。
    if (v && _family != null && _file != null) {
      await registerFontFile(_family!, _file!);
    }
    _enabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
  }

  /// 选择自定义字体（[family] 族名 + [file] 文件名），注册进引擎 + 写盘 + 通知。
  /// 不在此处改 enabled（开关由用户显式控制）。
  Future<void> setFont(String family, String file) async {
    await ensureLoaded();
    if (_family == family && _file == file) {
      // 族名/文件未变也重新注册：冷启动后引擎字体集合可能为空（上次关闭状态
      // 重启时 registerCurrentFont 跳过注册），此时重选同一字体若直接早退，
      // 字体仍未注册、不生效（反馈：重选同一字体无效，须换字体才生效）。
      await registerFontFile(family, file);
      return;
    }
    _family = family;
    _file = file;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFamily, family);
    await prefs.setString(_keyFile, file);
    // 即时注册（失败静默，冷启动 registerCurrentFont 会再兜底）
    await registerFontFile(family, file);
  }

  Future<void> setTextScale(double v) async {
    await ensureLoaded();
    final c = v.clamp(minTextScale, maxTextScale);
    if ((_textScale - c).abs() < 0.001) return;
    _textScale = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTextScale, c);
  }

  Future<void> setFontWeightIndex(int v) async {
    await ensureLoaded();
    final c = v.clamp(-1, 8);
    if (_fontWeight == c) return;
    _fontWeight = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyFontWeight, c);
  }

  /// 测试用：恢复默认值并清加载标记（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void resetForTest() {
    _loadFuture = null;
    _enabled = false;
    _family = null;
    _file = null;
    _textScale = 1.0;
    _fontWeight = -1;
    notifyListeners();
  }
}
