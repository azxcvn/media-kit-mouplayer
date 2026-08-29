import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_danmaku_settings_panel.dart';
import 'package:moumou/services/danmaku_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕设置面板回归测试（阶段2）：
/// - 两段式布局齐全：弹幕样式（5 滑杆 + 随机渐变色开关）与
///   弹幕配置（2 滑杆 + 5 开关）；
/// - 滑杆拖动 / 开关切换写设置单例（重栅格化项字号/字重/描边松手提交，
///   轻量项实时写）；
/// - 恢复默认按钮一键回默认值。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DanmakuSettings.instance.resetForTest();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlayerDanmakuSettingsPanel()),
    ));
    await tester.pumpAndSettle();
  }

  /// 面板内容超出视口时先滚动到目标可见再交互
  Future<void> ensureVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
  }

  testWidgets('两段式布局齐全：样式 + 配置 + 恢复默认', (tester) async {
    await pumpPanel(tester);
    expect(tester.takeException(), isNull);
    // 分组标题
    expect(find.text('弹幕样式'), findsOneWidget);
    expect(find.text('弹幕配置'), findsOneWidget);
    // 样式滑杆
    expect(find.text('弹幕字号'), findsOneWidget);
    expect(find.text('字体字重'), findsOneWidget);
    expect(find.text('弹幕速度'), findsOneWidget);
    expect(find.text('描边粗细'), findsOneWidget);
    expect(find.text('不透明度'), findsOneWidget);
    // 随机渐变色
    expect(find.text('随机渐变色'), findsOneWidget);
    // 配置滑杆
    expect(find.text('显示区域'), findsOneWidget);
    expect(find.text('弹幕行高'), findsOneWidget);
    // 配置开关
    expect(find.text('顶部弹幕'), findsOneWidget);
    expect(find.text('底部弹幕'), findsOneWidget);
    expect(find.text('滚动弹幕'), findsOneWidget);
    expect(find.text('海量弹幕'), findsOneWidget);
    expect(find.text('弹幕去重'), findsOneWidget);
    // 弹幕偏移
    expect(find.text('弹幕偏移'), findsOneWidget);
    expect(find.text('时间轴偏移'), findsOneWidget);
    expect(find.text('提前 1 秒'), findsOneWidget);
    expect(find.text('延后 1 秒'), findsOneWidget);
    expect(find.text('重置偏移'), findsOneWidget);
    // 恢复默认
    expect(find.text('恢复默认设置'), findsOneWidget);
  });

  testWidgets('开关切换实时写设置（随机渐变色 / 海量弹幕 / 去重）', (tester) async {
    await pumpPanel(tester);
    final s = DanmakuSettings.instance;
    // Switch 组件定位：按标签找行内的 Switch（value 初始 false → tap 开）
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(6)); // 随机色 + 3 显隐 + 海量 + 去重
    // 随机渐变色是样式区第一个 Switch（index 0，首屏可见）
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(s.randomColor, isTrue);
    // 去重是最后一个 Switch（视口外，先滚动到可见）
    await ensureVisible(tester, switches.last);
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(s.deduplication, isTrue);
  });

  testWidgets('滑杆拖动松手后写设置（字号）', (tester) async {
    await pumpPanel(tester);
    final s = DanmakuSettings.instance;
    expect(s.fontSize, 16);
    // 找到字号滑杆：第一个 Slider（样式区第一行）
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(8)); // 5 样式 + 2 配置 + 1 偏移
    // 字号滑杆（index 0）拖到最右端附近：10–30，拖到 90% 处；松手提交
    final bounds = tester.getRect(sliders.first);
    await tester.drag(sliders.first, Offset(bounds.width * 0.9, 0));
    await tester.pumpAndSettle();
    expect(s.fontSize, greaterThan(20));
  });

  testWidgets('偏移快捷按钮：提前/延后 1 秒 + 单独重置', (tester) async {
    await pumpPanel(tester);
    final s = DanmakuSettings.instance;
    expect(s.timeOffsetSeconds, 0);

    // 延后 1 秒（视口外，先滚动到可见）
    await ensureVisible(tester, find.text('延后 1 秒'));
    await tester.tap(find.text('延后 1 秒'));
    await tester.pumpAndSettle();
    expect(s.timeOffsetSeconds, 1);

    // 提前 1 秒（同行，回到 0）
    await tester.tap(find.text('提前 1 秒'));
    await tester.pumpAndSettle();
    expect(s.timeOffsetSeconds, 0);

    // 单独重置：只复位偏移，不影响其它设置（全局重置未触发）
    await s.setFontSize(24);
    await s.setTimeOffset(60);
    expect(s.timeOffsetSeconds, 60);
    await ensureVisible(tester, find.text('重置偏移'));
    await tester.tap(find.text('重置偏移'));
    await tester.pumpAndSettle();
    expect(s.timeOffsetSeconds, 0);
    expect(s.fontSize, 24);
  });

  testWidgets('恢复默认按钮：改值后一键回默认', (tester) async {
    await pumpPanel(tester);
    final s = DanmakuSettings.instance;
    // 先改两个值
    await s.setFontSize(24);
    await s.setShowTop(false);
    expect(s.fontSize, 24);
    expect(s.showTop, isFalse);
    // 点恢复默认（视口外，先滚动到可见）
    await ensureVisible(tester, find.text('恢复默认设置'));
    await tester.tap(find.text('恢复默认设置'));
    await tester.pumpAndSettle();
    expect(s.fontSize, 16);
    expect(s.showTop, isTrue);
  });

  testWidgets('设置变化后面板读数联动刷新（ListenableBuilder）', (tester) async {
    await pumpPanel(tester);
    expect(find.text('16'), findsOneWidget); // 字号读数
    await DanmakuSettings.instance.setFontSize(24);
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
  });
}
