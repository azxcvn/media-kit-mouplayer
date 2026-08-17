import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_speed_panel.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 倍速面板回归测试：
/// - 我的预设「✕」单个删除；
/// - 「添加到预设」随滑杆值联动禁用/恢复；
/// - 外部切倍速（点预设）后面板 UI 实时刷新（不重开面板）；
/// - 按钮两行布局：第一行三胶囊不换行，第二行「重置预设」。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerControlsSettings.instance.reset();
  });

  late ValueNotifier<double> speed;

  Future<void> pumpPanel(WidgetTester tester) async {
    speed = ValueNotifier<double>(1.0);
    addTearDown(speed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: PlayerSpeedPanel(
              speedListenable: speed,
              onSpeedChanged: (v) => speed.value = v,
              onTemporaryApply: (v) => speed.value = v,
              onReset: () => speed.value = 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// 取大数字读数（fontSize 30 的那个 Text）
  String bigNumber(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((t) => t.style?.fontSize == 30)
      .data!;

  testWidgets('外部切倍速后面板实时刷新（无需重开）', (tester) async {
    await pumpPanel(tester);
    await tester.pumpAndSettle();

    // 初始：大数字 1.0x
    expect(bigNumber(tester), '1.0x');

    // 模拟点击预设 2.0x（外部改变实际倍速）
    speed.value = 2.0;
    await tester.pump();
    // 大数字立即刷新，无需重开面板
    expect(bigNumber(tester), '2.0x');

    // 再切到 0.5x
    speed.value = 0.5;
    await tester.pump();
    expect(bigNumber(tester), '0.50x');
  });

  testWidgets('按钮两行布局：第一行三胶囊不换行，第二行重置预设', (tester) async {
    await pumpPanel(tester);
    await tester.pumpAndSettle();

    final y1 = tester.getTopLeft(find.text('临时应用')).dy;
    final y2 = tester.getTopLeft(find.text('添加到预设')).dy;
    final y3 = tester.getTopLeft(find.text('归位')).dy;
    final yReset = tester.getTopLeft(find.text('重置预设')).dy;

    // 三个胶囊同一行（y 坐标一致）
    expect(y1, y2);
    expect(y2, y3);
    // 重置预设单独在下面一行
    expect(yReset, greaterThan(y3));
  });

  testWidgets('我的预设「✕」可单个删除', (tester) async {
    final s = PlayerControlsSettings.instance;
    await s.addCustomSpeedPreset(1.3);
    await s.addCustomSpeedPreset(2.8);

    await pumpPanel(tester);
    await tester.pumpAndSettle();

    // 两个自定义预设都显示
    expect(find.text('1.30x'), findsOneWidget);
    expect(find.text('2.80x'), findsOneWidget);

    // 点击第一个 ✕ → 仅移除 1.3
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(s.customSpeedPresets, [2.8]);
    expect(find.text('1.30x'), findsNothing);
    expect(find.text('2.80x'), findsOneWidget);

    // 再点第二个 ✕ → 全部移除，「我的预设」区消失
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(s.customSpeedPresets, isEmpty);
    expect(find.text('2.80x'), findsNothing);
    expect(find.text('我的预设'), findsNothing);
  });

  testWidgets('「添加到预设」随滑杆值联动禁用/恢复', (tester) async {
    final s = PlayerControlsSettings.instance;
    await pumpPanel(tester);
    await tester.pumpAndSettle();

    Color? buttonColor() =>
        tester.widget<Text>(find.text('添加到预设')).style?.color;

    // 初始候选 = 1.0（系统预设）→ 置灰不可点
    expect(buttonColor(), Colors.white38);

    // 滑到 2.7（非任何预设）→ 恢复主题色可点
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(2.7);
    await tester.pump();
    expect(buttonColor(), isNot(Colors.white38));

    // 点击「添加到预设」→ 写入我的预设，按钮再次置灰
    await tester.tap(find.text('添加到预设'));
    await tester.pumpAndSettle();
    expect(s.customSpeedPresets, [2.7]);
    expect(buttonColor(), Colors.white38);
  });
}
