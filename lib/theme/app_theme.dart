import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';

/// 主题定义：根据 seed 色生成浅色 / 深色 / AMOLED 纯黑三种 ThemeData
class AppTheme {
  /// 统一 AppBar 样式：
  /// - [backgroundColor] 显式固定为 surface，滚动到内容下方时背景不再被
  ///   替换为 surfaceContainer（Flutter M3 的滚动变色机制），消除视觉切换
  /// - [scrolledUnderElevation] 置 0，滚动时不叠加阴影/色调
  static AppBarTheme _appBarTheme(ColorScheme scheme) => AppBarTheme(
    scrolledUnderElevation: 0,
    backgroundColor: scheme.surface,
  );

  /// 用 flex_seed_scheme 的 SeedColorScheme 生成配色方案，
  /// 支持 21 种 FlexSchemeVariant 调色板风格
  static ColorScheme _scheme(
    Color seed,
    FlexSchemeVariant variant,
    Brightness brightness,
  ) {
    return SeedColorScheme.fromSeeds(
      brightness: brightness,
      primaryKey: seed,
      variant: variant,
    );
  }

  static ThemeData light(
    Color seed,
    FlexSchemeVariant variant, {
    String? fontFamily,
    FontWeight? fontWeight,
  }) {
    final scheme = _scheme(seed, variant, Brightness.light);
    return _withFont(
      ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: fontFamily,
        appBarTheme: _appBarTheme(scheme),
      ),
      fontWeight,
    );
  }

  static ThemeData dark(
    Color seed,
    FlexSchemeVariant variant, {
    String? fontFamily,
    FontWeight? fontWeight,
  }) {
    final scheme = _scheme(seed, variant, Brightness.dark);
    return _withFont(
      ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: fontFamily,
        appBarTheme: _appBarTheme(scheme),
      ),
      fontWeight,
    );
  }

  /// AMOLED 纯黑：把所有 surface 系列压到纯黑/近黑，背景纯黑
  static ThemeData amoled(
    Color seed,
    FlexSchemeVariant variant, {
    String? fontFamily,
    FontWeight? fontWeight,
  }) {
    final scheme = _scheme(seed, variant, Brightness.dark).copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF232323),
    );
    return _withFont(
      ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: fontFamily,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: _appBarTheme(scheme),
      ),
      fontWeight,
    );
  }

  /// 应用统一字重（全量覆盖 textTheme 各样式，不保留内置字重层级；
  /// 对齐 PiliPlus 做法）。[fontWeight] 为 null 时原样返回。
  static ThemeData _withFont(ThemeData base, FontWeight? fontWeight) {
    if (fontWeight == null) return base;
    TextStyle w(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(fontWeight: fontWeight);
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        displayLarge: w(t.displayLarge),
        displayMedium: w(t.displayMedium),
        displaySmall: w(t.displaySmall),
        headlineLarge: w(t.headlineLarge),
        headlineMedium: w(t.headlineMedium),
        headlineSmall: w(t.headlineSmall),
        titleLarge: w(t.titleLarge),
        titleMedium: w(t.titleMedium),
        titleSmall: w(t.titleSmall),
        bodyLarge: w(t.bodyLarge),
        bodyMedium: w(t.bodyMedium),
        bodySmall: w(t.bodySmall),
        labelLarge: w(t.labelLarge),
        labelMedium: w(t.labelMedium),
        labelSmall: w(t.labelSmall),
      ),
    );
  }
}
