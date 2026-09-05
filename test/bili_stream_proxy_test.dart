import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/bilibili/bili_stream_proxy.dart';

void main() {
  test('代理转发远程流字节并透传 Range / 响应头', () async {
    late String receivedRange;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      receivedRange = req.headers.value('range') ?? '';
      expect(req.headers.value('referer'), 'https://www.bilibili.com');
      req.response.statusCode = HttpStatus.partialContent; // 206
      req.response.headers.set('content-type', 'video/mp4');
      req.response.headers.set('content-range', 'bytes 0-3/10');
      req.response.add([1, 2, 3, 4]);
      await req.response.close();
    });

    final proxy = BiliStreamProxy();
    final reg = await proxy.registerStreams(
      videoUrl: 'http://127.0.0.1:${upstream.port}/video',
      headers: {'Referer': 'https://www.bilibili.com'},
    );
    expect(reg, isNotNull);
    expect(reg!.videoUrl, startsWith('http://127.0.0.1:'));

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(reg.videoUrl));
    req.headers.set('Range', 'bytes=0-3');
    final resp = await req.close();
    expect(resp.statusCode, 206);
    final bytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(bytes, [1, 2, 3, 4]);
    expect(receivedRange, 'bytes=0-3');
    expect(resp.headers.value('content-range'), 'bytes 0-3/10');

    proxy.stop();
    client.close();
    await upstream.close(force: true);
  });

  test('未注册的路径返回 404', () async {
    final proxy = BiliStreamProxy();
    final base = await proxy.start();
    expect(base, isNotNull);
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('$base/nope'));
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.notFound);
    await resp.drain<void>();
    proxy.stop();
    client.close();
  });

  test('start/stop 生命周期', () async {
    final proxy = BiliStreamProxy();
    final base = await proxy.start();
    expect(base, isNotNull);
    expect(proxy.isRunning, isTrue);
    proxy.stop();
    expect(proxy.isRunning, isFalse);
  });

  test('recentSpeedBytesPerSec：未知 URL 返回 null，已注册 URL 返回速率', () async {
    final proxy = BiliStreamProxy();
    expect(proxy.recentSpeedBytesPerSec('http://127.0.0.1:1/unknown'), isNull);

    final reg = await proxy.registerStreams(videoUrl: 'http://127.0.0.1:1/v');
    expect(reg, isNotNull);
    // 已注册但尚未传输：速率为 0（非 null），保证 UI 有确定值可显示。
    expect(proxy.recentSpeedBytesPerSec(reg!.videoUrl), 0.0);
    proxy.stop();
  });

  test('recentTotalSpeedBytesPerSec：无流 null / 注册后为聚合速率', () async {
    final proxy = BiliStreamProxy();
    expect(proxy.recentTotalSpeedBytesPerSec(), isNull);

    // video + audio 双流注册（B 站 DASH），聚合查询不依赖 URL 匹配
    final reg = await proxy.registerStreams(
      videoUrl: 'http://127.0.0.1:1/v',
      audioUrl: 'http://127.0.0.1:1/a',
    );
    expect(reg, isNotNull);
    // 已注册但尚未传输：聚合速率为 0（非 null）
    expect(proxy.recentTotalSpeedBytesPerSec(), 0.0);

    // stop 清空注册后回到 null（播放页 dispose 调 stop，状态栏不会读到残留）
    proxy.stop();
    expect(proxy.recentTotalSpeedBytesPerSec(), isNull);
  });
}
