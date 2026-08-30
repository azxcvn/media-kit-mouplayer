import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_danmaku_settings_panel.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器暗色面板强调色跟随主题（字幕/弹幕面板滑杆不再写死 0xFF4FC3F7）。
///
/// 断言方式：同一面板在两种主题色下渲染，取实际生效的 [SliderThemeData]
/// 比较——颜色必须不同，且都由该主题色派生（不等于旧的写死蓝）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 旧实现写死的强调色（回归哨兵：任何主题下都不该恰好等于它）
  const legacyAccent = Color(0xFF4FC3F7);

  Future<SliderThemeData> sliderThemeUnderSeed(
    WidgetTester tester,
    Color seed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
          ),
        ),
        home: const Scaffold(body: PlayerDanmakuSettingsPanel()),
      ),
    );
    await tester.pumpAndSettle();
    // 取滑杆实际继承到的主题（面板内 SliderTheme 包裹的那一层）
    return SliderTheme.of(
      tester.element(find.byType(Slider).first),
    );
  }

  testWidgets('弹幕设置面板滑杆：换主题色 → 轨道/拇指颜色随之改变', (tester) async {
    final orange = await sliderThemeUnderSeed(tester, const Color(0xFFFF9800));
    final orangeActive = orange.activeTrackColor;
    final orangeThumb = orange.thumbColor;

    final purple = await sliderThemeUnderSeed(tester, const Color(0xFF9C27B0));

    expect(orangeActive, isNotNull);
    expect(orangeThumb, isNotNull);
    expect(
      purple.activeTrackColor,
      isNot(orangeActive),
      reason: '滑杆活动轨道必须跟随主题色',
    );
    expect(purple.thumbColor, isNot(orangeThumb), reason: '拇指必须跟随主题色');
    // 回归哨兵：不再是写死的那支蓝
    expect(orangeActive, isNot(legacyAccent));
    expect(purple.activeTrackColor, isNot(legacyAccent));
  });

  testWidgets('滑杆不显示拖拽气泡（保留 Kazumi 外观）', (tester) async {
    final theme = await sliderThemeUnderSeed(tester, const Color(0xFF4CAF50));
    expect(theme.showValueIndicator, ShowValueIndicator.never);
  });

  testWidgets('playerPanelAccent：由主题 primary 派生，浅色主题下也可读', (tester) async {
    late Color accentFromLight;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.light,
          ),
        ),
        home: Builder(
          builder: (context) {
            accentFromLight = playerPanelAccent(context);
            return const SizedBox();
          },
        ),
      ),
    );

    // 面板恒为暗底：强调色需派生自暗色方案（比浅色主题的 primary 更亮）
    final lightPrimary = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ).primary;
    expect(accentFromLight, isNot(lightPrimary));
    expect(
      accentFromLight.computeLuminance(),
      greaterThan(lightPrimary.computeLuminance()),
      reason: '暗底面板上的强调色应更亮，保证对比度',
    );
  });

  testWidgets('派生结果按 seed 缓存（同 seed 复用同一实例，避免逐帧重算）', (tester) async {
    late ColorScheme first;
    late ColorScheme second;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00A1D6),
            brightness: Brightness.dark,
          ),
        ),
        home: Builder(
          builder: (context) {
            first = playerPanelScheme(context);
            second = playerPanelScheme(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(identical(first, second), isTrue);
  });
}
