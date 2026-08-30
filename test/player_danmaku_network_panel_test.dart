import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/pages/player/views/player_danmaku_network_panel.dart';
import 'package:moumou/services/danmaku_network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络弹幕搜索面板 UI 测试（工作.md 第 4 点重设计）：
/// 紧凑胶囊搜索框（40dp 定高）、搜索框下方关键词历史胶囊 + 「清除」胶囊、
/// 命中后自动折叠搜索框（点折叠条重新展开）、结果卡展开/收起动画
/// （AnimationController 驱动，收起态不构建子树）、选集回调 + 关闭面板。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    DanmakuNetworkService? service,
    void Function(DandanAnime, DandanEpisode, String?)? onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerDanmakuNetworkPanel(
            networkService: service ?? _FakeNetworkService(),
            onEpisodeSelected: onSelected ?? (a, e, s) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    // 用键盘搜索动作触发 onSubmitted（比点击 suffix 图标更稳定）
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('无历史无结果：显示空态提示', (tester) async {
    await pumpPanel(tester);
    expect(find.text('输入关键词搜索网络弹幕'), findsOneWidget);
  });

  testWidgets('搜索结果：标题 + 胶囊小标签（类型/集数/来源服务器）', (tester) async {
    await pumpPanel(tester);
    await search(tester, '紫罗兰');
    expect(find.text('紫罗兰永恒花园'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('2 集'), findsOneWidget);
    expect(find.text('OVA'), findsOneWidget);
    expect(find.text('我的服务器'), findsOneWidget); // 自建来源胶囊
    expect(find.text('弹弹Play（默认）'), findsNothing); // 默认服务器不标注
  });

  testWidgets('结果卡展开/收起动画：收起态不构建集列表，展开后可见，再点收起', (tester) async {
    await pumpPanel(tester);
    await search(tester, '紫罗兰');

    // 收起态：子树完全不构建（零布局开销）
    expect(find.text('第01话'), findsNothing);

    // 展开：动画中途高度已推进但未到位，结束后集列表可点
    await tester.tap(find.text('紫罗兰永恒花园'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('第01话'), findsOneWidget); // 已构建，仍在动画中
    await tester.pumpAndSettle();
    expect(find.text('第01话').hitTestable(), findsOneWidget);
    expect(find.text('第02话').hitTestable(), findsOneWidget);

    // 再点收起：动画结束后子树重新卸载
    await tester.tap(find.text('紫罗兰永恒花园'));
    await tester.pumpAndSettle();
    expect(find.text('第01话'), findsNothing);
  });

  testWidgets('手风琴：展开第二张卡自动收起第一张', (tester) async {
    await pumpPanel(tester);
    await search(tester, '紫罗兰');

    await tester.tap(find.text('紫罗兰永恒花园'));
    await tester.pumpAndSettle();
    expect(find.text('第01话').hitTestable(), findsOneWidget);

    await tester.tap(find.text('另一部番'));
    await tester.pumpAndSettle();
    expect(find.text('第01话'), findsNothing);
    expect(find.text('正片').hitTestable(), findsOneWidget);
  });

  testWidgets('搜索框紧凑：胶囊容器定高 40dp', (tester) async {
    await pumpPanel(tester);
    final box = tester.getSize(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Container),
      ).first,
    );
    expect(box.height, 40);
  });

  testWidgets('点选集 → 触发回调并关闭面板', (tester) async {
    DandanAnime? gotAnime;
    DandanEpisode? gotEpisode;
    String? gotServer;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: PlayerDanmakuNetworkPanel(
                        networkService: _FakeNetworkService(),
                        onEpisodeSelected: (a, e, s) {
                          gotAnime = a;
                          gotEpisode = e;
                          gotServer = s;
                        },
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await search(tester, '紫罗兰');
    await tester.tap(find.text('紫罗兰永恒花园'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第01话'));
    await tester.pumpAndSettle();

    expect(gotEpisode?.episodeId, 11);
    expect(gotAnime?.animeId, 1);
    expect(gotServer, isNull);
    // 面板已关闭，回到 home
    expect(find.text('第01话'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('关键词历史：搜索框下方胶囊展示 + 末尾「清除」胶囊', (tester) async {
    SharedPreferences.setMockInitialValues({
      'danmaku_search_history': jsonEncode(['紫罗兰', '海贼王']),
    });
    await pumpPanel(tester);
    expect(find.text('紫罗兰'), findsOneWidget);
    expect(find.text('海贼王'), findsOneWidget);
    // 历史胶囊紧贴搜索框下方（无独立分组卡片/分组标签）
    expect(find.text('搜索历史'), findsNothing);
    expect(
      tester.getTopLeft(find.text('紫罗兰')).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
    );

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('紫罗兰'), findsNothing);
    expect(find.text('海贼王'), findsNothing);
    expect(find.text('输入关键词搜索网络弹幕'), findsOneWidget);
  });

  testWidgets('命中结果后自动折叠搜索框，点折叠条重新展开', (tester) async {
    SharedPreferences.setMockInitialValues({
      'danmaku_search_history': jsonEncode(['海贼王']),
    });
    await pumpPanel(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('海贼王'), findsOneWidget);

    await search(tester, '紫罗兰');
    // 搜索框与历史胶囊让位给结果区，只剩「关键词 · N 部」折叠条
    expect(find.byType(TextField), findsNothing);
    expect(find.text('海贼王'), findsNothing);
    expect(find.text('清除'), findsNothing);
    expect(find.text('2 部'), findsOneWidget);

    await tester.tap(find.text('2 部'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('紫罗兰永恒花园'), findsOneWidget); // 结果仍在
  });

  testWidgets('搜索无结果时搜索框保持展开（便于立刻改词）', (tester) async {
    await pumpPanel(tester);
    await search(tester, '空');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('未找到相关番剧'), findsOneWidget);
  });

  testWidgets('点历史胶囊 → 填入关键词并搜索', (tester) async {
    SharedPreferences.setMockInitialValues({
      'danmaku_search_history': jsonEncode(['紫罗兰']),
    });
    await pumpPanel(tester);
    await tester.tap(find.text('紫罗兰'));
    await tester.pumpAndSettle();
    expect(find.text('紫罗兰永恒花园'), findsOneWidget);
  });

  testWidgets('搜索失败显示错误横幅', (tester) async {
    await pumpPanel(tester);
    await search(tester, '错');
    expect(find.textContaining('搜索失败'), findsOneWidget);
  });
}

/// 测试假网络服务（真实 [DanmakuNetworkService] 会发起 HTTP 请求，
/// 单元测试环境用固定结果替代）。
class _FakeNetworkService extends DanmakuNetworkService {
  _FakeNetworkService();

  @override
  Future<DanmakuSearchResult> search(String keyword) async {
    if (keyword == '错') {
      return const DanmakuSearchResult(items: [], errors: ['弹弹Play（默认）: 超时']);
    }
    if (keyword == '空') {
      return const DanmakuSearchResult(items: [], errors: []);
    }
    return DanmakuSearchResult(
      items: [
        DanmakuSearchItem(
          anime: const DandanAnime(
            animeId: 1,
            animeTitle: '紫罗兰永恒花园',
            type: 'tv',
            typeDescription: 'TV',
            episodes: [
              DandanEpisode(episodeId: 11, episodeTitle: '第01话'),
              DandanEpisode(episodeId: 12, episodeTitle: '第02话'),
            ],
          ),
          serverUrl: null,
          serverName: '弹弹Play（默认）',
        ),
        DanmakuSearchItem(
          anime: const DandanAnime(
            animeId: 2,
            animeTitle: '另一部番',
            type: 'ova',
            typeDescription: 'OVA',
            episodes: [DandanEpisode(episodeId: 21, episodeTitle: '正片')],
          ),
          serverUrl: 'https://self.example.com',
          serverName: '我的服务器',
        ),
      ],
      errors: const [],
    );
  }
}
