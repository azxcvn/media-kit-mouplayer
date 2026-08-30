import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_auto_match_cache.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/services/danmaku_auto_match_cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕自动匹配缓存存储测试（切集自动匹配弹幕，工作.md 第 7 点）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const episodes = [
    DandanEpisode(episodeId: 1, episodeTitle: '第01话'),
    DandanEpisode(episodeId: 2, episodeTitle: '第02话'),
  ];

  test('保存并读回（含 serverUrl null 与自建地址）', () async {
    final store = DanmakuAutoMatchCacheStore();
    expect(await store.load(), isNull);
    await store.save(const DanmakuAutoMatchCache(
      animeId: 10,
      animeTitle: '紫罗兰永恒花园',
      serverUrl: null,
      episodes: episodes,
    ));
    final cache = await store.load();
    expect(cache, isNotNull);
    expect(cache!.animeId, 10);
    expect(cache.animeTitle, '紫罗兰永恒花园');
    expect(cache.serverUrl, isNull);
    expect(cache.episodes.length, 2);
  });

  test('serverUrl 自建地址持久化', () async {
    final store = DanmakuAutoMatchCacheStore();
    await store.save(const DanmakuAutoMatchCache(
      animeId: 10,
      animeTitle: '番剧',
      serverUrl: 'https://self.com',
      episodes: episodes,
    ));
    expect((await store.load())!.serverUrl, 'https://self.com');
  });

  test('持久化：新实例读取同一存储（模拟重启）', () async {
    final first = DanmakuAutoMatchCacheStore();
    await first.save(const DanmakuAutoMatchCache(
      animeId: 10,
      animeTitle: '番剧',
      serverUrl: null,
      episodes: episodes,
    ));
    final second = DanmakuAutoMatchCacheStore();
    expect((await second.load())!.animeTitle, '番剧');
  });

  test('清空缓存', () async {
    final store = DanmakuAutoMatchCacheStore();
    await store.save(const DanmakuAutoMatchCache(
      animeId: 10,
      animeTitle: '番剧',
      serverUrl: null,
      episodes: episodes,
    ));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('损坏数据：防御性回退 null', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_auto_match_cache': 'not-a-json{',
    });
    final store = DanmakuAutoMatchCacheStore();
    expect(await store.load(), isNull);
  });
}
