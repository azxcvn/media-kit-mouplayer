import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 右侧面板（showPlayerPanel）回归测试：
/// - 面板内 ListTile/SwitchListTile 需要 Material 外壳（历史红底黄字崩溃）；
/// - 面板内页面栈导航（编辑控制栏 push）正常工作。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerControlsSettings.instance.reset();
  });

  test('动作图标均为有效 IconData', () {
    for (final a in PlayerTopAction.values) {
      expect(a.icon, isNotNull);
    }
    expect(Icons.tune, isNotNull);
    expect(Icons.restart_alt, isNotNull);
    expect(Icons.more_horiz, isNotNull);
  });

  testWidgets('showPlayerPanel 打开面板 + 编辑页跳转不崩溃', (tester) async {
    // 预先放置两个动作，模拟用户已配置槽位
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.speed);
    await s.addTopAction(PlayerTopAction.subtitle);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  showPlayerPanel(context, pages: [
                    PlayerPanelPage(
                      title: '控制栏',
                      body: _buildMockMorePanel(),
                    ),
                  ]);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('控制栏'), findsOneWidget);
    // 已放置的动作显示在面板列表中
    expect(find.text('倍速'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('编辑控制栏'), findsOneWidget);

    // 点击「编辑控制栏」→ 面板内就地切换（无新面板、无崩溃）
    await tester.tap(find.text('编辑控制栏'));
    await tester.pumpAndSettle();
    expect(find.text('编辑页'), findsOneWidget);
  });
}

Widget _buildMockMorePanel() {
  // 与真实 _buildMorePanel 一致：必须用 Builder 取面板树内的 context，
  // PlayerPanelNavigator.of 要求调用方位于 _PanelNavigatorScope 之下
  // （历史 bug：用 State/外层 context 调用会断言 scope == null）。
  return Builder(
    builder: (panelContext) => ListenableBuilder(
      listenable: PlayerControlsSettings.instance,
      builder: (context, _) {
        final actions = PlayerControlsSettings.instance.topActions;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon, color: Colors.white),
                title: Text(
                  a.label,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {},
              ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.tune, color: Colors.white),
              title: const Text(
                '编辑控制栏',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                PlayerPanelNavigator.of(panelContext).push(
                  PlayerPanelPage(
                    title: '编辑控制栏',
                    body: const Center(child: Text('编辑页')),
                  ),
                );
              },
            ),
          ],
        );
      },
    ),
  );
}
