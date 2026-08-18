import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_seek_bar.dart';
import 'package:moumou/pages/player/views/portrait_player_bottom_bar.dart';

/// 竖屏播放页底栏布局回归测试（v3 更新）：
/// - 时间文本位于「下一集」按钮右侧、同一行（v3 用户反馈：改回此款式）；
/// - 下一集按钮左缘 = kPlayerLeftInset（人体工学左对齐，与返回/进度条开端同 x）；
/// - PlayerSeekBar 为自定义绘制进度条（无 Material Slider，用户反馈
///   「进度条难拖」修复）：轨道左缘精确落在 kPlayerLeftInset、右缘留
///   rightInset（横竖屏共用同一进度条组件）；
/// - 右侧按钮簇顺序（从左到右）：超分辨率 → 列表 → 倍速 → 选择屏幕
///   （即从右到左：选择屏幕 → 倍速 → 列表 → 超分辨率，工作.md 第 18 点）。
void main() {
  Widget buildBar() {
    return MaterialApp(
      home: Scaffold(
        body: PortraitPlayerBottomBar(
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
        ),
      ),
    );
  }

  testWidgets('时间在下一集右侧同一行，下一集左缘对齐 kPlayerLeftInset', (tester) async {
    await tester.pumpWidget(buildBar());
    expect(tester.takeException(), isNull);

    // 时间文本在「下一集」右侧、同一行（v3 布局）
    final nextRect = tester.getRect(find.byTooltip('下一集'));
    final timeRect = tester.getRect(find.text('00:01 / 00:10'));
    expect(timeRect.left > nextRect.right, isTrue);
    expect((timeRect.center.dy - nextRect.center.dy).abs() < 1, isTrue);
    // 下一集左缘 = kPlayerLeftInset（与返回/进度条开端同 x）
    expect(nextRect.left, kPlayerLeftInset);
    // 进度条为自定义绘制（无 Material Slider）：轨道左缘精确落在
    // kPlayerLeftInset、右缘留 rightInset（横竖屏共用同一组件）。
    final seekRect = tester.getRect(find.byType(PlayerSeekBar));
    final rail = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color ==
              Colors.white.withValues(alpha: 0.3),
    );
    expect(rail, findsOneWidget);
    final railRect = tester.getRect(rail);
    expect(railRect.left - seekRect.left, kPlayerLeftInset);
    expect(seekRect.right - railRect.right, PlayerSeekBar.rightInset);
  });

  testWidgets('右侧按钮簇顺序：超分辨率→列表→倍速→选择屏幕（左到右）', (tester) async {
    await tester.pumpWidget(buildBar());
    expect(tester.takeException(), isNull);

    final srDx = tester.getTopLeft(find.text('超分辨率')).dx;
    final listDx = tester.getTopLeft(find.byIcon(Icons.playlist_play)).dx;
    final speedDx = tester.getTopLeft(find.byIcon(Icons.speed_rounded)).dx;
    final switchDx =
        tester.getTopLeft(find.byIcon(Icons.screen_rotation)).dx;

    expect(srDx < listDx, isTrue);
    expect(listDx < speedDx, isTrue);
    expect(speedDx < switchDx, isTrue);
    // 全部在同一行（垂直居中于同一 Row，比较中心 y）
    final srCenter = tester.getRect(find.text('超分辨率')).center.dy;
    final switchCenter =
        tester.getRect(find.byIcon(Icons.screen_rotation)).center.dy;
    expect((srCenter - switchCenter).abs() < 1, isTrue);
  });

  testWidgets('窄屏（360dp）下底栏不溢出（v3 RenderFlex 溢出修复）', (tester) async {
    // 模拟窄屏竖屏（如 1080×2400 @3x → 360×800 dp）
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildBar());
    // 若操作行仍溢出，Flutter 测试会通过 FlutterError.reportError 报 overflow，
    // takeException 会捕获（RenderFlex overflow 在测试中按异常上报）
    expect(tester.takeException(), isNull);
    // 时间文本仍在（Flexible + ellipsis 不丢组件）
    expect(find.text('00:01 / 00:10'), findsOneWidget);
  });
}
