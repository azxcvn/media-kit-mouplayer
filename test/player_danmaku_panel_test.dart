import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/pages/player/views/player_danmaku_panel.dart';
import 'package:moumou/services/danmaku_network_service.dart';
import 'package:moumou/services/danmaku_service.dart';

/// 弹幕二级界面回归测试（阶段1+3）：
/// - 四个入口齐全：本地弹幕 / 网络弹幕 / 自动匹配 / 弹幕设置；
/// - 网络弹幕 / 自动匹配点击触发注入回调（阶段3 实现）；
/// - 弹幕设置点击触发注入回调（与底栏弹幕设置按钮同一回调）；
/// - 本地弹幕在无平台通道的测试环境（getSdkInt → 0）下点击不崩溃。
void main() {
  Widget buildPanel({
    required DanmakuController controller,
    VoidCallback? onSettingsTap,
    VoidCallback? onNetworkTap,
    VoidCallback? onAutoMatchTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerDanmakuPanel(
          controller: controller,
          onSettingsTap: onSettingsTap ?? () {},
          onNetworkTap: onNetworkTap,
          onAutoMatchTap: onAutoMatchTap,
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

  testWidgets('网络弹幕点击 → 触发注入回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildPanel(
      controller: _FakeDanmakuController(),
      onNetworkTap: () => tapped = true,
    ));
    await tester.tap(find.text('网络弹幕'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('自动匹配点击 → 触发注入回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildPanel(
      controller: _FakeDanmakuController(),
      onAutoMatchTap: () => tapped = true,
    ));
    await tester.tap(find.text('自动匹配'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('未注入回调时点击弹「即将上线」提示（兜底）', (tester) async {
    await tester.pumpWidget(buildPanel(controller: _FakeDanmakuController()));
    await tester.tap(find.text('网络弹幕'));
    await tester.pumpAndSettle();
    expect(find.text('「网络弹幕」功能即将上线'), findsOneWidget);
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
  void Function(String message)? onNetworkDanmakuLoaded;

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

  @override
  Future<bool> loadNetworkDanmaku({
    required int episodeId,
    required String animeTitle,
    required String episodeTitle,
    String? serverUrl,
  }) async =>
      false;

  @override
  Future<List<DanmakuMatchItem>> matchCurrentVideo() async => const [];

  @override
  Future<void> saveAutoMatchCache({
    required int animeId,
    required String animeTitle,
    required String? serverUrl,
    required List<DandanEpisode> episodes,
  }) async {}

  @override
  Future<List<DandanEpisode>?> fetchAnimeEpisodes({
    required int animeId,
    required String animeTitle,
    String? serverUrl,
  }) async =>
      null;
}
