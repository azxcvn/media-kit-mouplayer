import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/widgets/speed_dial_fab.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<SpeedDialAction> actions) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: SpeedDialFab(actions: actions),
        ),
      ),
    );
  }

  testWidgets('初始收起：只显示主按钮，不显示选项', (tester) async {
    await pump(tester, [
      SpeedDialAction(icon: Icons.history, label: '最近播放', onTap: () {}),
      SpeedDialAction(icon: Icons.link, label: '打开链接', onTap: () {}),
    ]);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('最近播放'), findsNothing);
    expect(find.text('打开链接'), findsNothing);
  });

  testWidgets('点击展开后显示全部选项，选中动作后收起并回调', (tester) async {
    var tapped = '';
    await pump(tester, [
      SpeedDialAction(icon: Icons.history, label: '最近播放', onTap: () {}),
      SpeedDialAction(icon: Icons.cloud_outlined, label: '网络存储', onTap: () => tapped = 'network'),
    ]);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('最近播放'), findsOneWidget);
    expect(find.text('网络存储'), findsOneWidget);

    await tester.tap(find.text('网络存储'));
    await tester.pumpAndSettle();

    expect(tapped, 'network');
    expect(find.text('网络存储'), findsNothing);
    expect(find.text('最近播放'), findsNothing);
  });

  testWidgets('再次点击主按钮可收起', (tester) async {
    await pump(tester, [
      SpeedDialAction(icon: Icons.history, label: '最近播放', onTap: () {}),
    ]);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('最近播放'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('最近播放'), findsNothing);
  });
}