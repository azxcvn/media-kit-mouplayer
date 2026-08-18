import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/player_bottom_panel.dart';
import 'package:moumou/widgets/player_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 竖屏底部面板（showPlayerBottomPanel）回归测试：
/// - 面板从底部弹出且内容正常渲染（Material 外壳，防 "No Material widget found"）；
/// - 面板内页面栈导航（编辑控制栏 push / 返回 / 关闭）正常工作。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerControlsSettings.instance.reset();
  });

  testWidgets('showPlayerBottomPanel 弹出 + 面板内二级导航 + 关闭', (tester) async {
    // 预先放置两个动作，模拟用户已配置槽位
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.subtitle);
    await s.addTopAction(PlayerTopAction.danmaku);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  showPlayerBottomPanel(context, pages: [
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
    // 面板主页：标题 + 已启用动作列表
    expect(find.text('控制栏'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('弹幕'), findsOneWidget);
    expect(find.text('编辑控制栏'), findsOneWidget);

    // 点击「编辑控制栏」→ 面板内就地切换二级页（无新面板、无崩溃）
    await tester.tap(find.text('编辑控制栏'));
    await tester.pumpAndSettle();
    expect(find.text('编辑页'), findsOneWidget);

    // 二级页出现返回按钮 → 返回主页
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('控制栏'), findsOneWidget);

    // 关闭按钮 → 面板关闭
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('控制栏'), findsNothing);
  });
}

Widget _buildMockMorePanel() {
  // 与竖屏播放页 _buildMorePanel 一致：必须用 Builder 取面板树内的 context，
  // PlayerBottomPanelNavigator.of 要求调用方位于 _BottomPanelNavigatorScope 之下。
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
                PlayerBottomPanelNavigator.of(panelContext).push(
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
