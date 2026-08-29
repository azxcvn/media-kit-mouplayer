import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_bottom_bar.dart';

/// 横屏播放页底栏回归测试（v3 布局回归修复 + 弹幕第 5 点）：
/// - 右侧按钮簇（超分/列表/倍速/选择屏幕）必须**贴屏幕右缘**——
///   时间文本不得用 Flexible 包裹（会与 Spacer 平分自由空间，
///   把按钮推向中间，历史回归根因）；
/// - 簇内顺序（从左到右）：超分辨率 → 列表 → 倍速 → 选择屏幕
///   （即从右到左：选择屏幕 → 倍速 → 列表 → 超分辨率，工作.md 第 18 点）；
/// - 时间文本在「下一集」右侧同一行；
/// - 弹幕开关/设置按钮在时间文本右侧同一行（顺序：开关 → 设置），
///   开关图标随 danmakuOn 切换。
void main() {
  Widget buildBar({double width = 800, bool danmakuOn = true}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PlayerBottomBar(
              valueMs: 1000,
              maxMs: 10000,
              onSeekChanged: (_) {},
              onSeekEnd: (_) {},
              hasNext: true,
              onNext: () {},
              timeText: '00:01 / 00:10',
              onTimeTap: () {},
              onSpeedTap: () {},
              showSpeedButtonBackground: false,
              superResolutionLabel: '超分辨率',
              onSuperResolutionTap: () {},
              onScreenSwitchTap: () {},
              showScreenSwitchBackground: false,
              onPlaylistTap: () {},
              danmakuOn: danmakuOn,
              onDanmakuToggle: () {},
              onDanmakuSettingsTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('右侧按钮簇贴右缘 + 顺序正确（v3 回归：不再被推往中间）', (tester) async {
    await tester.pumpWidget(buildBar());
    expect(tester.takeException(), isNull);

    final switchRect = tester.getRect(find.byIcon(Icons.screen_rotation));
    // 最右按钮右缘距屏幕右缘 < 60px（右内边距 20 + 图标宽度）
    expect(
      (800 - switchRect.right).abs() < 60,
      isTrue,
      reason: '选择屏幕按钮应贴近屏幕右缘，而不是被推到中间',
    );

    // 簇内顺序（左到右）
    final srDx = tester.getTopLeft(find.text('超分辨率')).dx;
    final listDx = tester.getTopLeft(find.byIcon(Icons.playlist_play)).dx;
    final speedDx = tester.getTopLeft(find.byIcon(Icons.speed_rounded)).dx;
    final switchDx = switchRect.left;
    expect(srDx < listDx, isTrue);
    expect(listDx < speedDx, isTrue);
    expect(speedDx < switchDx, isTrue);

    // 时间文本在「下一集」右侧同一行
    final nextRect = tester.getRect(find.byTooltip('下一集'));
    final timeRect = tester.getRect(find.text('00:01 / 00:10'));
    expect(timeRect.left > nextRect.right, isTrue);
    expect((timeRect.center.dy - nextRect.center.dy).abs() < 1, isTrue);
  });

  testWidgets('弹幕开关/设置按钮在时间文本右侧同一行（顺序：开关 → 设置）',
      (tester) async {
    await tester.pumpWidget(buildBar());
    expect(tester.takeException(), isNull);

    final timeRect = tester.getRect(find.text('00:01 / 00:10'));
    final toggleRect = tester.getRect(find.byTooltip('关闭弹幕'));
    final settingRect = tester.getRect(find.byTooltip('弹幕设置'));

    // 时间文本 → 弹幕开关 → 弹幕设置（左到右）
    expect(toggleRect.left > timeRect.right, isTrue);
    expect(settingRect.left > toggleRect.right, isTrue);
    // 与时间文本同一行
    expect((toggleRect.center.dy - timeRect.center.dy).abs() < 1, isTrue);
    expect((settingRect.center.dy - timeRect.center.dy).abs() < 1, isTrue);
  });

  testWidgets('弹幕开关随 danmakuOn 切换图标与提示', (tester) async {
    await tester.pumpWidget(buildBar(danmakuOn: true));
    expect(find.byTooltip('关闭弹幕'), findsOneWidget);
    expect(find.byTooltip('打开弹幕'), findsNothing);

    await tester.pumpWidget(buildBar(danmakuOn: false));
    expect(find.byTooltip('打开弹幕'), findsOneWidget);
    expect(find.byTooltip('关闭弹幕'), findsNothing);
  });

  testWidgets('窄横屏（600dp）下不溢出', (tester) async {
    tester.view.physicalSize = const Size(1800, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildBar(width: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('极窄窗口（400dp，分屏/自由窗口压宽）下弹幕按钮不溢出',
      (tester) async {
    // 回归：Expanded 只剩几十 px 时固定尺寸弹幕按钮曾 RenderFlex 溢出，
    // 现由 FittedBox(scaleDown) 等比缩小兜底
    tester.view.physicalSize = const Size(1200, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildBar(width: 400));
    expect(tester.takeException(), isNull);
    // 弹幕按钮仍在（缩放渲染，不丢组件）
    expect(find.byTooltip('弹幕设置'), findsOneWidget);
  });
}
