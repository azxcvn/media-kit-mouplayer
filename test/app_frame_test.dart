import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/widgets/app_frame.dart';

/// AppFrame 全局框架测试：
/// - 播放页路由检测（AppFrameObserver）
/// - 普通页面避让底部安全区、播放页全屏（不消费任何系统栏 inset）
void main() {
  setUp(() {
    AppFrameObserver.instance.reset();
  });

  tearDown(() {
    AppFrameObserver.instance.reset();
  });

  Widget wrapApp({
    required EdgeInsets padding,
    required Widget home,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: AppFrame(child: child!),
      ),
      home: home,
    );
  }

  testWidgets('AppFrameObserver 识别播放页路由', (WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [AppFrameObserver.instance],
        home: const Scaffold(body: Text('home')),
      ),
    );
    expect(AppFrameObserver.instance.isPlayerTop.value, isFalse);

    // 推入带播放页标识的路由
    navKey.currentState!.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: playerRouteName),
        builder: (_) => const Scaffold(body: Text('player')),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppFrameObserver.instance.isPlayerTop.value, isTrue);

    // 弹出后恢复
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(AppFrameObserver.instance.isPlayerTop.value, isFalse);
  });

  testWidgets('普通页面：底部避让安全区', (WidgetTester tester) async {
    // 模拟底部 48px 系统导航键 + 左侧 24px 挖孔
    await tester.pumpWidget(
      wrapApp(
        padding: const EdgeInsets.fromLTRB(24, 0, 0, 48),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(Scaffold));
    // 屏幕默认 800x600：bottom 被消费 48 → 高度 552
    expect(rect.height, 552);
    // left 不被消费（AppFrame left 恒为 false）→ 从 0 开始
    expect(rect.left, 0);
  });

  testWidgets('播放页：全屏不消费任何安全区', (WidgetTester tester) async {
    AppFrameObserver.instance.isPlayerTop.value = true;
    await tester.pumpWidget(
      wrapApp(
        padding: const EdgeInsets.fromLTRB(24, 0, 0, 48),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(Scaffold));
    // 全屏 800x600：left/bottom 都不被消费
    expect(rect.left, 0);
    expect(rect.height, 600);
  });
}
