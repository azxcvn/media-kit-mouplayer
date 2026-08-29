import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/pages/player/views/subtitle_file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自建文件选择器面板回归测试（字幕/音频/弹幕三处共用同一面板）：
/// - 记忆文件夹已被删除（listDirectory 返回 null）→ 自动向上回退到最近
///   存活祖先打开（小喵 player 停在死路径卡死的教训，工作.md 弹幕阶段1）；
/// - 记忆文件夹存在但为空 → 正常落地（空列表 + 上级按钮可用，不卡死）；
/// - 进入一个不可读目录（导航失败）→ 维持原状，不落到死路径；
/// - 选择文件 → onPicked 回调 + 文件夹记忆写入。
void main() {
  const channel = MethodChannel('moumou/video_info');
  const root = '/storage/emulated/0';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'listDirectory') return null;
      final path = call.arguments['path'] as String;
      switch (path) {
        case root:
          return [
            {
              'name': 'Movies',
              'path': '$root/Movies',
              'isDirectory': true,
              'size': 0,
              'modifiedMs': 0,
            },
            {
              'name': 'EP01.srt',
              'path': '$root/EP01.srt',
              'isDirectory': false,
              'size': 1024,
              'modifiedMs': 0,
            },
          ];
        case '/empty/dir':
          // 真实存在但为空（文件已被删除）
          return <Map<String, dynamic>>[];
        default:
          // 其余路径（已删除的文件夹 / 不可读位置）→ null = 不可用
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget buildPanel() {
    return const MaterialApp(
      home: Scaffold(
        body: SubtitleFilePickerPanel(
          onPicked: _noopPicked,
          onClose: _noopClose,
        ),
      ),
    );
  }

  testWidgets('正常打开：默认根目录，目录与字幕文件都显示', (tester) async {
    await tester.pumpWidget(buildPanel());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('EP01.srt'), findsOneWidget);
    expect(find.text('上级'), findsOneWidget);
  });

  testWidgets('记忆文件夹已被删除 → 向上回退到存活祖先（不死锁在死路径）',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'subtitle_picker_last_folder': '$root/Gone',
    });
    await tester.pumpWidget(buildPanel());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 落在根目录（最近存活祖先），根内容可见，死路径不出现在界面上
    expect(find.text('Movies'), findsOneWidget);
    expect(find.textContaining('/Gone'), findsNothing);
  });

  testWidgets('记忆文件夹存在但为空 → 正常落地（空列表 + 上级可用）', (tester) async {
    SharedPreferences.setMockInitialValues({
      'subtitle_picker_last_folder': '/empty/dir',
    });
    await tester.pumpWidget(buildPanel());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 空目录：无文件行，路径仍在空目录上，上级按钮可见
    expect(find.text('Movies'), findsNothing);
    expect(find.text('dir'), findsOneWidget); // 路径标签的当前目录名
    expect(find.text('上级'), findsOneWidget);
    // 点击上级：/empty 不可读 → 维持原状（不落到死路径）
    await tester.tap(find.text('上级'));
    await tester.pumpAndSettle();
    expect(find.text('dir'), findsOneWidget);
    expect(find.text('Movies'), findsNothing);
  });

  testWidgets('选择文件 → onPicked 回调触发且记住所在文件夹', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleFilePickerPanel(
            onPicked: (path) async => picked = path,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('EP01.srt'));
    await tester.pumpAndSettle();
    expect(picked, '$root/EP01.srt');
    // 文件夹记忆：选中文件后写入其所在目录
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('subtitle_picker_last_folder'), root);
  });
}

Future<void> _noopPicked(String path) async {}
void _noopClose() {}
