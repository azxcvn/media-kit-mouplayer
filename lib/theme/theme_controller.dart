import 'package:flex_seed_scheme/flex_seed_scheme.dart';
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
  FlexSchemeVariant _variant = FlexSchemeVariant.tonalSpot;

  AppThemeMode get mode => _mode;
  Color get seedColor => _seedColor;
  FlexSchemeVariant get variant => _variant;

  /// 预设主题色（23 种：默认天蓝置首，其余按色相排列，名称统一 3 字）
  static const List<({Color color, String label})> presetColors = [
    (color: Color(0xFF00A1D6), label: '天蓝色'),
    (color: Color(0xFF2196F3), label: '蓝色'),
    (color: Color(0xFF03A9F4), label: '浅蓝色'),
    (color: Color(0xFF3F51B5), label: '靛蓝色'),
    (color: Color(0xFF00BCD4), label: '蓝绿色'),
    (color: Color(0xFF009688), label: '青色'),
    (color: Color(0xFF4CAF50), label: '绿色'),
    (color: Color(0xFF5CB67B), label: '薄荷绿'),
    (color: Color(0xFF8BC34A), label: '浅绿色'),
    (color: Color(0xFFCDDC39), label: '酸橙色'),
    (color: Color(0xFFFFEB3B), label: '黄色'),
    (color: Color(0xFFFFC107), label: '琥珀色'),
    (color: Color(0xFFFF9800), label: '橙色'),
    (color: Color(0xFFF57C00), label: '橙红色'),
    (color: Color(0xFFF44336), label: '红色'),
    (color: Color(0xFFFF7299), label: '粉红色'),
    (color: Color(0xFFFF6699), label: '亮粉色'),
    (color: Color(0xFF6750A4), label: '紫罗兰'),
    (color: Color(0xFF9C27B0), label: '紫色'),
    (color: Color(0xFF673AB7), label: '深紫色'),
    (color: Color(0xFF607D8B), label: '蓝灰色'),
    (color: Color(0xFF795548), label: '棕色'),
    (color: Color(0xFF9E9E9E), label: '灰色'),
  ];

  /// 调色板风格（flex_seed_scheme 的 21 种 FlexSchemeVariant，名称统一 3 字）
  static const Map<FlexSchemeVariant, String> variantLabels = {
    FlexSchemeVariant.tonalSpot: '标准型',
    FlexSchemeVariant.fidelity: '保真型',
    FlexSchemeVariant.monochrome: '单色型',
    FlexSchemeVariant.neutral: '中性型',
    FlexSchemeVariant.vibrant: '鲜艳型',
    FlexSchemeVariant.expressive: '鲜明型',
    FlexSchemeVariant.content: '柔和型',
    FlexSchemeVariant.rainbow: '彩虹型',
    FlexSchemeVariant.fruitSalad: '果味型',
    FlexSchemeVariant.candyPop: '糖果型',
    FlexSchemeVariant.chroma: '饱和型',
    FlexSchemeVariant.highContrast: '对比型',
    FlexSchemeVariant.jolly: '欢快型',
    FlexSchemeVariant.material: '经典型',
    FlexSchemeVariant.material3Legacy: '旧版型',
    FlexSchemeVariant.oneHue: '单色相',
    FlexSchemeVariant.soft: '淡雅型',
    FlexSchemeVariant.ultraContrast: '超对比',
    FlexSchemeVariant.vivid: '生动型',
    FlexSchemeVariant.vividBackground: '亮背景',
    FlexSchemeVariant.vividSurfaces: '亮表面',
  };

  /// 旧版持久化迁移：Flutter DynamicSchemeVariant 的 index（0-7）→
  /// FlexSchemeVariant 对应值（枚举顺序不同，必须显式映射）
  static const List<FlexSchemeVariant> _legacyVariantMapping = [
    FlexSchemeVariant.tonalSpot, // 0 tonalSpot
    FlexSchemeVariant.neutral, // 1 neutral
    FlexSchemeVariant.vibrant, // 2 vibrant
    FlexSchemeVariant.expressive, // 3 expressive
    FlexSchemeVariant.content, // 4 content
    FlexSchemeVariant.monochrome, // 5 monochrome
    FlexSchemeVariant.rainbow, // 6 rainbow
    FlexSchemeVariant.fruitSalad, // 7 fruitSalad
  ];

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
    if (variantIndex != null && variantIndex >= 0) {
      if (variantIndex < _legacyVariantMapping.length) {
        // 旧数据：按 DynamicSchemeVariant 顺序映射
        _variant = _legacyVariantMapping[variantIndex];
      } else if (variantIndex < FlexSchemeVariant.values.length) {
        _variant = FlexSchemeVariant.values[variantIndex];
      }
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

  Future<void> setVariant(FlexSchemeVariant variant) async {
    if (_variant == variant) return;
    _variant = variant;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVariant, variant.index);
  }
}
