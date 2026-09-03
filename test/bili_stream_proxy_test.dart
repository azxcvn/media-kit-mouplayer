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
}
