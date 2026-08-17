import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/home/home_page.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 权限流程测试：未授权显示「授予权限」，点击授权后进入扫描流程。
class MockPermissionHandlerPlatform extends PermissionHandlerPlatform {
  final Map<Permission, PermissionStatus> statuses = {};

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return statuses[permission] ?? PermissionStatus.denied;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    // 请求即视为授权
    return {for (final p in permissions) p: PermissionStatus.granted};
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async {
    return false;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  const channel = MethodChannel('moumou/video_info');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PermissionHandlerPlatform.instance = MockPermissionHandlerPlatform();
    // 扫描接口 mock：默认返回空视频库
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVideos') return <dynamic>[];
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('权限未授权时显示「授予权限」入口', (WidgetTester tester) async {
    final mock = PermissionHandlerPlatform.instance
        as MockPermissionHandlerPlatform;
    mock.statuses[Permission.manageExternalStorage] = PermissionStatus.denied;

    await tester.pumpWidget(
      MaterialApp(home: HomePage(viewSettings: ViewSettings())),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要授予存储权限才能扫描视频'), findsOneWidget);
    expect(find.text('授予权限'), findsOneWidget);
  });

  testWidgets('权限已授权时直接扫描（空库显示无视频）', (WidgetTester tester) async {
    final mock = PermissionHandlerPlatform.instance
        as MockPermissionHandlerPlatform;
    mock.statuses[Permission.manageExternalStorage] = PermissionStatus.granted;

    await tester.pumpWidget(
      MaterialApp(home: HomePage(viewSettings: ViewSettings())),
    );
    await tester.pumpAndSettle();

    expect(find.text('授予权限'), findsNothing);
    expect(find.text('没有找到视频'), findsOneWidget);
  });

  testWidgets('点击「授予权限」后进入扫描流程', (WidgetTester tester) async {
    final mock = PermissionHandlerPlatform.instance
        as MockPermissionHandlerPlatform;
    mock.statuses[Permission.manageExternalStorage] = PermissionStatus.denied;

    await tester.pumpWidget(
      MaterialApp(home: HomePage(viewSettings: ViewSettings())),
    );
    await tester.pumpAndSettle();
    expect(find.text('授予权限'), findsOneWidget);

    // 模拟用户在系统授权页开启权限后返回
    mock.statuses[Permission.manageExternalStorage] = PermissionStatus.granted;

    await tester.tap(find.text('授予权限'));
    await tester.pumpAndSettle();

    // 授权后重新加载 → 空视频库 → 显示无视频
    expect(find.text('没有找到视频'), findsOneWidget);
    expect(find.text('授予权限'), findsNothing);
  });
}
