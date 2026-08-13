import 'package:flutter/material.dart';

/// 主题定义：根据 seed 色生成浅色 / 深色 / AMOLED 纯黑三种 ThemeData
class AppTheme {
  static ThemeData light(Color seed, DynamicSchemeVariant variant) =>
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          dynamicSchemeVariant: variant,
        ),
      );

  static ThemeData dark(Color seed, DynamicSchemeVariant variant) =>
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          dynamicSchemeVariant: variant,
        ),
      );

  /// AMOLED 纯黑：把所有 surface 系列压到纯黑/近黑，背景纯黑
  static ThemeData amoled(Color seed, DynamicSchemeVariant variant) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: variant,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF232323),
      ),
      scaffoldBackgroundColor: Colors.black,
    );
  }
}
