import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式
enum AppThemeMode {
  system('跟随系统'),
  light('浅色'),
  dark('深色'),
  amoled('AMOLED 纯黑');

  final String label;
  const AppThemeMode(this.label);
}

/// 主题控制器：管理主题模式与主题色，并持久化到本地
class ThemeController extends ChangeNotifier {
  static const _keyMode = 'theme_mode';
  static const _keySeed = 'theme_seed_color';
  static const _keyVariant = 'theme_variant';

  AppThemeMode _mode = AppThemeMode.system;
  Color _seedColor = const Color(0xFF00A1D6);
  DynamicSchemeVariant _variant = DynamicSchemeVariant.tonalSpot;

  AppThemeMode get mode => _mode;
  Color get seedColor => _seedColor;
  DynamicSchemeVariant get variant => _variant;

  /// 预设主题色
  static const List<Color> presetColors = [
    Color(0xFF00A1D6), // 蓝
    Color(0xFF5CB67B), // 绿
    Color(0xFF6750A4), // 紫
    Color(0xFFFF6699), // 粉
    Color(0xFFF57C00), // 橙
    Color(0xFFE53935), // 红
    Color(0xFF00ACC1), // 青
    Color(0xFFFDD835), // 黄
  ];

  /// 调色板风格（Material 3 官方变体）
  static const Map<DynamicSchemeVariant, String> variantLabels = {
    DynamicSchemeVariant.tonalSpot: '默认',
    DynamicSchemeVariant.neutral: '中性',
    DynamicSchemeVariant.vibrant: '鲜艳',
    DynamicSchemeVariant.expressive: '鲜明',
    DynamicSchemeVariant.content: '柔和',
    DynamicSchemeVariant.monochrome: '单色',
    DynamicSchemeVariant.rainbow: '彩虹',
    DynamicSchemeVariant.fruitSalad: '果味',
  };

  /// 启动时从本地恢复
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_keyMode);
    final seedValue = prefs.getInt(_keySeed);
    final variantIndex = prefs.getInt(_keyVariant);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < AppThemeMode.values.length) {
      _mode = AppThemeMode.values[modeIndex];
    }
    if (seedValue != null) {
      _seedColor = Color(seedValue);
    }
    if (variantIndex != null &&
        variantIndex >= 0 &&
        variantIndex < DynamicSchemeVariant.values.length) {
      _variant = DynamicSchemeVariant.values[variantIndex];
    }
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, mode.index);
  }

  Future<void> setSeedColor(Color color) async {
    if (_seedColor == color) return;
    _seedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeed, color.toARGB32());
  }

  Future<void> setVariant(DynamicSchemeVariant variant) async {
    if (_variant == variant) return;
    _variant = variant;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVariant, variant.index);
  }
}
