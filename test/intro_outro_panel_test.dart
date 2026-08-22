import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_intro_outro_panel.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 片头片尾面板回归测试：
/// - 开关关闭时只显示开关行，开启后展开片头/片尾设置段；
/// - 秒数输入实时写入设置并换算 mm:ss；
/// - 滑杆拖动写入设置；
/// - 「设为当前时间 / 设为当前剩余时间」按位置/时长取数；
/// - 范围输入收窄秒数联动；
/// - 一键重置：秒数清零、范围回默认。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IntroOutroSettings.instance.resetForTest();
  });

  final s = IntroOutroSettings.instance;

  late ValueNotifier<Duration> position;
  late ValueNotifier<Duration> duration;

  Future<void> pumpPanel(WidgetTester tester) async {
    position = ValueNotifier(Duration.zero);
    duration = ValueNotifier(const Duration(seconds: 600));
    addTearDown(position.dispose);
    addTearDown(duration.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: PlayerIntroOutroPanel(
              positionListenable: position,
              durationListenable: duration,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('开关关闭只显示开关行；开启后展开设置段', (tester) async {
    await pumpPanel(tester);

    // 关闭：无片头/片尾段与重置按钮
    expect(find.text('启用跳过片头片尾'), findsOneWidget);
    expect(find.text('跳过片头'), findsNothing);
    expect(find.text('一键重置'), findsNothing);

    // 开启：展开
    await s.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('跳过片头'), findsOneWidget);
    expect(find.text('跳过片尾'), findsOneWidget);
    expect(find.text('一键重置'), findsOneWidget);
  });

  testWidgets('秒数输入实时写入设置并换算 mm:ss', (tester) async {
    await s.setEnabled(true);
    await pumpPanel(tester);

    // 片头秒数输入 90 → 显示 01:30
    await tester.enterText(find.byType(TextField).first, '90');
    await tester.pumpAndSettle();
    expect(s.introSeconds, 90);
    expect(find.text('01:30'), findsOneWidget);

    // 超范围输入钳制到范围上限 180 → 03:00
    await tester.enterText(find.byType(TextField).first, '9999');
    await tester.pumpAndSettle();
    expect(s.introSeconds, 180);
    expect(find.text('03:00'), findsOneWidget);
  });

  testWidgets('滑杆拖动写入设置（0 – 范围）', (tester) async {
    await s.setEnabled(true);
    await pumpPanel(tester);

    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChanged!(120);
    await tester.pumpAndSettle();
    expect(s.introSeconds, 120);
    expect(find.text('02:00'), findsOneWidget);
  });

  testWidgets('「设为当前时间」取当前位置；片尾取剩余时间', (tester) async {
    await s.setEnabled(true);
    await pumpPanel(tester);

    // 位置 100s → 片头跳过秒数 100
    position.value = const Duration(seconds: 100);
    await tester.tap(find.text('设为当前时间'));
    await tester.pumpAndSettle();
    expect(s.introSeconds, 100);

    // 位置 590s / 总长 600s → 片尾跳过秒数 = 剩余 10
    position.value = const Duration(seconds: 590);
    await tester.tap(find.text('设为当前剩余时间'));
    await tester.pumpAndSettle();
    expect(s.outroSeconds, 10);
    expect(find.text('00:10'), findsOneWidget);
  });

  testWidgets('范围输入收窄秒数联动', (tester) async {
    await s.setEnabled(true);
    await s.setIntroSeconds(150);
    await pumpPanel(tester);
    expect(find.text('02:30'), findsOneWidget);

    // 片头范围输入 60 → 秒数 150 收窄到 60
    await tester.enterText(find.byType(TextField).at(1), '60');
    await tester.pumpAndSettle();
    expect(s.introRange, 60);
    expect(s.introSeconds, 60);
    expect(find.text('01:00'), findsOneWidget);
  });

  testWidgets('一键重置：秒数清零、范围回默认', (tester) async {
    await s.setEnabled(true);
    await s.setIntroSeconds(90);
    await s.setOutroSeconds(45);
    await s.setIntroRange(300);
    await s.setOutroRange(500);
    await pumpPanel(tester);

    await tester.tap(find.text('一键重置'));
    await tester.pumpAndSettle();
    expect(s.introSeconds, 0);
    expect(s.outroSeconds, 0);
    expect(s.introRange, IntroOutroSettings.defaultRangeSeconds);
    expect(s.outroRange, IntroOutroSettings.defaultRangeSeconds);
    expect(find.text('00:00'), findsNWidgets(2));
  });
}
