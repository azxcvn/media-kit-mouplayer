import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/danmaku_search_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络弹幕搜索历史存储测试（工作.md 第 4 点）：
/// 去重、上限淘汰最旧、一键清除、持久化、损坏数据防御。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('记录并读回（新→旧）', () async {
    final history = DanmakuSearchHistory();
    await history.add('紫罗兰');
    await history.add('海贼王');
    expect(await history.load(), ['海贼王', '紫罗兰']);
  });

  test('重复关键词去重并提到最前', () async {
    final history = DanmakuSearchHistory();
    await history.add('a');
    await history.add('b');
    await history.add('a');
    expect(await history.load(), ['a', 'b']);
  });

  test('空白关键词忽略', () async {
    final history = DanmakuSearchHistory();
    await history.add('   ');
    expect(await history.load(), isEmpty);
  });

  test('上限淘汰最旧（默认 10 条）', () async {
    final history = DanmakuSearchHistory();
    for (var i = 1; i <= 12; i++) {
      await history.add('k$i');
    }
    final items = await history.load();
    expect(items.length, 10);
    expect(items.first, 'k12'); // 最新在前
    expect(items.last, 'k3'); // k1/k2 被淘汰
  });

  test('自定义上限', () async {
    final history = DanmakuSearchHistory(maxEntries: 3);
    for (var i = 1; i <= 5; i++) {
      await history.add('k$i');
    }
    expect(await history.load(), ['k5', 'k4', 'k3']);
  });

  test('一键清除', () async {
    final history = DanmakuSearchHistory();
    await history.add('a');
    await history.add('b');
    await history.clear();
    expect(await history.load(), isEmpty);
  });

  test('持久化：新实例读取同一存储（模拟重启）', () async {
    final first = DanmakuSearchHistory();
    await first.add('紫罗兰');
    final second = DanmakuSearchHistory();
    expect(await second.load(), ['紫罗兰']);
  });

  test('损坏数据：防御性回退空历史且可继续写入', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_search_history': 'not-a-json{',
    });
    final history = DanmakuSearchHistory();
    expect(await history.load(), isEmpty);
    await history.add('新词');
    expect(await history.load(), ['新词']);
  });
}
