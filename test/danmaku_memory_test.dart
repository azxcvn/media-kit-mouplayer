import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/danmaku_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕手动导入记忆存储测试（按视频路径持久化，重启软件可恢复）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('set / get：记录并读回', () async {
    final memory = DanmakuManualMemory();
    expect(await memory.get('/a/video.mp4'), isNull);
    await memory.set('/a/video.mp4', '/a/video.danmaku.xml');
    expect(await memory.get('/a/video.mp4'), '/a/video.danmaku.xml');
  });

  test('持久化：新实例读取同一存储（模拟重启软件）', () async {
    final first = DanmakuManualMemory();
    await first.set('/a/video.mp4', '/files/danmaku/a.xml');

    // 新实例（模拟进程重启后重新构造）
    final second = DanmakuManualMemory();
    expect(await second.get('/a/video.mp4'), '/files/danmaku/a.xml');
  });

  test('多视频互不干扰（一视频一条记忆）', () async {
    final memory = DanmakuManualMemory();
    await memory.set('/a/video.mp4', '/files/danmaku/a.xml');
    await memory.set('/b/EP02.mp4', '/files/danmaku/b.xml');
    expect(await memory.get('/a/video.mp4'), '/files/danmaku/a.xml');
    expect(await memory.get('/b/EP02.mp4'), '/files/danmaku/b.xml');
    // 重新手动选择 → 覆盖旧记忆
    await memory.set('/a/video.mp4', '/files/danmaku/a2.xml');
    expect(await memory.get('/a/video.mp4'), '/files/danmaku/a2.xml');
    expect(await memory.get('/b/EP02.mp4'), '/files/danmaku/b.xml');
  });

  test('remove：清除该视频记忆（记忆的弹幕文件失效场景）', () async {
    final memory = DanmakuManualMemory();
    await memory.set('/a/video.mp4', '/files/danmaku/a.xml');
    await memory.set('/b/EP02.mp4', '/files/danmaku/b.xml');
    await memory.remove('/a/video.mp4');
    expect(await memory.get('/a/video.mp4'), isNull);
    expect(await memory.get('/b/EP02.mp4'), '/files/danmaku/b.xml');
    // 重复 remove 不抛异常
    await memory.remove('/a/video.mp4');
  });

  test('损坏的 JSON 数据：防御性回退无记忆（不抛异常）', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_manual_memory': 'not-a-json{',
    });
    final memory = DanmakuManualMemory();
    expect(await memory.get('/a/video.mp4'), isNull);
    // 之后仍可正常写入
    await memory.set('/a/video.mp4', '/files/danmaku/a.xml');
    expect(await memory.get('/a/video.mp4'), '/files/danmaku/a.xml');
  });

  test('非字符串值 / 非字符串键：过滤丢弃', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_manual_memory': '{"123": 456, "/a/video.mp4": "/a.xml"}',
    });
    final memory = DanmakuManualMemory();
    expect(await memory.get('123'), isNull);
    expect(await memory.get('/a/video.mp4'), '/a.xml');
  });

  test('toast 去重：第一次提示 / 已提示不再提示 / 持久化', () async {
    final memory = DanmakuManualMemory();
    expect(await memory.hasShownAutoLoadToast('/a/video.mp4'), isFalse);
    await memory.markAutoLoadToastShown('/a/video.mp4');
    expect(await memory.hasShownAutoLoadToast('/a/video.mp4'), isTrue);
    // 幂等：重复标记不抛异常
    await memory.markAutoLoadToastShown('/a/video.mp4');

    // 新实例（模拟重启软件）：已提示记录仍保留，且不影响其它视频
    final second = DanmakuManualMemory();
    expect(await second.hasShownAutoLoadToast('/a/video.mp4'), isTrue);
    expect(await second.hasShownAutoLoadToast('/b/EP02.mp4'), isFalse);
  });

  test('toast 去重：损坏数据防御性回退', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_auto_toasted': 'not-a-json{',
    });
    final memory = DanmakuManualMemory();
    expect(await memory.hasShownAutoLoadToast('/a/video.mp4'), isFalse);
    await memory.markAutoLoadToastShown('/a/video.mp4');
    expect(await memory.hasShownAutoLoadToast('/a/video.mp4'), isTrue);
  });
}
