import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/player_danmaku_panel.dart';
import 'package:moumou/services/danmaku_service.dart';

/// 弹幕二级界面回归测试（阶段1）：
/// - 四个入口齐全：本地弹幕 / 网络弹幕 / 自动匹配 / 弹幕设置；
/// - 网络弹幕 / 自动匹配点击 toast 提示待上线；
/// - 弹幕设置点击触发注入回调（与底栏弹幕设置按钮同一回调）；
/// - 本地弹幕在无平台通道的测试环境（getSdkInt → 0）下点击不崩溃。
void main() {
  Widget buildPanel({
    required DanmakuController controller,
    VoidCallback? onSettingsTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerDanmakuPanel(
          controller: controller,
          onSettingsTap: onSettingsTap ?? () {},
        ),
      ),
    );
  }

  testWidgets('四个入口齐全', (tester) async {
    await tester.pumpWidget(buildPanel(controller: _FakeDanmakuController()));
    expect(tester.takeException(), isNull);
    expect(find.text('本地弹幕'), findsOneWidget);
    expect(find.text('网络弹幕'), findsOneWidget);
    expect(find.text('自动匹配'), findsOneWidget);
    expect(find.text('弹幕设置'), findsOneWidget);
  });

  testWidgets('网络弹幕点击 → toast 提示待上线', (tester) async {
    await tester.pumpWidget(buildPanel(controller: _FakeDanmakuController()));
    await tester.tap(find.text('网络弹幕'));
    await tester.pumpAndSettle();
    expect(find.text('「网络弹幕」功能即将上线'), findsOneWidget);
  });

  testWidgets('自动匹配点击 → toast 提示待上线', (tester) async {
    await tester.pumpWidget(buildPanel(controller: _FakeDanmakuController()));
    await tester.tap(find.text('自动匹配'));
    await tester.pumpAndSettle();
    expect(find.text('「自动匹配」功能即将上线'), findsOneWidget);
  });

  testWidgets('弹幕设置点击 → 触发注入回调（与底栏设置按钮同一行为）', (tester) async {
    var settingsTapped = false;
    await tester.pumpWidget(buildPanel(
      controller: _FakeDanmakuController(),
      onSettingsTap: () => settingsTapped = true,
    ));
    await tester.tap(find.text('弹幕设置'));
    await tester.pumpAndSettle();
    expect(settingsTapped, isTrue);
  });

  testWidgets('本地弹幕点击（测试环境无平台通道）不崩溃', (tester) async {
    await tester.pumpWidget(buildPanel(controller: _FakeDanmakuController()));
    await tester.tap(find.text('本地弹幕'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// 测试假控制器（真实 [DanmakuController] 需要绑定 media_kit Player，
/// 单元测试环境不初始化原生播放器；面板 UI 测试只依赖其接口）。
class _FakeDanmakuController extends ChangeNotifier
    implements DanmakuController {
  @override
  void Function(String fileName)? onAutoLoadedDanmaku;

  @override
  bool get danmakuOn => true;

  @override
  int get danmakuCount => 0;

  @override
  void attachLayer(canvas.DanmakuController<void> layer) {}

  @override
  void detachLayer(canvas.DanmakuController<void> layer) {}

  @override
  void toggle() {}

  @override
  void setDanmakuOn(bool value) {}

  @override
  Future<void> loadForVideo(String mediaPath) async {}

  @override
  Future<bool> loadDanmakuFromFile(String path) async => false;
}
