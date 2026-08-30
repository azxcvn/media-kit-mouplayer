import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_server.dart';
import 'package:moumou/pages/settings/danmaku_server_page.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕服务器设置页 UI 测试（工作.md 第 7 点收尾：互斥限制的呈现）：
/// 默认弹弹Play 服务器启用时「切集自动匹配弹幕」开关变灰 + 副标题给出原因 +
/// 点击弹 toast；停用默认服务器后开关恢复可用。
void main() {
  final settings = DanmakuServerSettings.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.resetForTest();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DanmakuServerPage()));
    await tester.pumpAndSettle();
  }

  /// 「切集自动匹配弹幕」那一行的 Switch（服务器卡片也有 Switch，按行定位）
  Switch autoMatchSwitch(WidgetTester tester) => tester.widget<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('切集自动匹配弹幕'),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Switch),
        ),
      );

  testWidgets('默认服务器启用时：开关变灰（onChanged == null）+ 副标题给出短原因', (tester) async {
    await pumpPage(tester);

    expect(autoMatchSwitch(tester).onChanged, isNull, reason: '禁用 = 变灰');
    // 变灰必须配文本提示，不能让用户以为是 bug
    expect(find.text('请先停用弹弹Play 服务器'), findsOneWidget);
    expect(find.text('切集时自动匹配并加载对应集弹幕'), findsNothing);
  });

  testWidgets('副标题文案显著短于 toast 完整说明（窄屏不挤的前提）', (tester) async {
    await pumpPage(tester);

    // 说明：不断言像素行数——测试字体是 Ahem（每个字形都是等宽方块），
    // 会把中文行宽算得远大于真实 CJK 字体，像素断言在测试环境没有意义。
    // 这里改断言「字符数」这一字体无关的量：副标题必须明显更短。
    final short = settings.autoMatchBlockedReason!;
    final full = settings.autoMatchBlockedMessage!;
    expect(short.length, lessThan(16), reason: '副标题需短到窄屏单行');
    expect(short.length * 2, lessThan(full.length), reason: '完整说明留给 toast');
    expect(find.text(short), findsOneWidget);
  });

  testWidgets('变灰状态下点击该行 → 弹 toast 给出完整说明', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(kAutoMatchBlockedTapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    // toast 承载副标题放不下的完整解释（含服务器名与开关名）
    final toastText = find.descendant(
      of: find.byType(SnackBar),
      matching: find.textContaining(DanmakuServer.defaultName),
    );
    expect(toastText, findsOneWidget);
    expect(
      (tester.widget<Text>(toastText).data)!,
      allOf(contains('不可开启'), contains('切集自动匹配弹幕')),
    );
    // 点击不得偷偷改状态
    expect(settings.autoMatchPreference, isFalse);
  });

  testWidgets('停用默认服务器后：开关恢复可用，可正常开启', (tester) async {
    await settings.setServerEnabled(DanmakuServer.defaultId, false);
    await pumpPage(tester);

    expect(autoMatchSwitch(tester).onChanged, isNotNull);
    expect(find.text('切集时自动匹配并加载对应集弹幕'), findsOneWidget);
    expect(find.text('请先停用弹弹Play 服务器'), findsNothing);

    await tester.tap(find.text('切集自动匹配弹幕'));
    await tester.pumpAndSettle();
    expect(settings.autoMatchEnabled, isTrue);
    expect(autoMatchSwitch(tester).value, isTrue);
  });

  testWidgets('已开启后重新启用默认服务器 → 开关回落为关且变灰', (tester) async {
    await settings.setServerEnabled(DanmakuServer.defaultId, false);
    await settings.setAutoMatchEnabled(true);
    await pumpPage(tester);
    expect(autoMatchSwitch(tester).value, isTrue);

    // 在页面上直接启用默认服务器（服务器卡片的开关）
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text(DanmakuServer.defaultName),
          matching: find.byType(Card),
        ),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(autoMatchSwitch(tester).value, isFalse, reason: '互斥 → 立即不生效');
    expect(autoMatchSwitch(tester).onChanged, isNull);
    expect(settings.autoMatchPreference, isTrue, reason: '偏好保留待恢复');
  });
}
