/// 本地 HTTP 流代理：解决 libmpv 内置 mbedTLS 与 B 站 CDN 的 TLS 兼容问题。
///
/// 背景（小喵 player 的修复经验，commit 49537c3d）：mpv 内核用 mbedTLS 做
/// HTTPS，与部分 B 站 CDN（upos-*.bilivideo.com）的 TLS 握手不兼容，导致
/// 部分番剧放不出来。小喵的解法是用 OkHttp（Android 原生 TLS）做本地代理，
/// mpv 改从 localhost 明文播放。
///
/// 本实现沿用同一思路、改为纯 Dart：用 `dart:io` 的 [HttpClient]（底层
/// BoringSSL，即 Chrome 同源 TLS，兼容 B 站 CDN）拉取远程流，本地
/// [HttpServer] 监听 `127.0.0.1` 明文转发给 mpv。mpv 只与 localhost 通信，
/// 不再触碰 mbedTLS 的 HTTPS 栈。转发 Range 头以支持拖动进度。
library;

import 'dart:async';
import 'dart:io';

/// 一次代理注册的结果（video/audio 的本地 URL）。
class BiliStreamRegistration {
  final String videoUrl;
  final String? audioUrl;

  const BiliStreamRegistration({required this.videoUrl, this.audioUrl});
}

class _StreamEntry {
  final String url;
  final Map<String, String> headers;

  const _StreamEntry(this.url, this.headers);
}

class BiliStreamProxy {
  BiliStreamProxy({HttpClient? client})
      : _client = client ?? (HttpClient()..autoUncompress = false);

  static final BiliStreamProxy instance = BiliStreamProxy();

  final HttpClient _client;
  final Map<String, _StreamEntry> _streams = <String, _StreamEntry>{};
  HttpServer? _server;
  int _port = 0;
  int _seq = 0;

  String get _baseUrl => 'http://127.0.0.1:$_port';

  bool get isRunning => _server != null;

  /// 启动代理（幂等）。返回 base URL；失败返回 null。
  Future<String?> start() async {
    if (_server != null) return _baseUrl;
    try {
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen(_handle);
      return _baseUrl;
    } catch (_) {
      _server = null;
      _port = 0;
      return null;
    }
  }

  /// 注册视频（必填）+ 音频（可选）流，返回对应的本地 URL。
  /// 每次注册用唯一路径（`v{seq}`/`a{seq}`），保证重开（切画质）时 URL
  /// 变化、mpv 一定重新拉流，而非复用旧连接。
  /// 代理启动失败返回 null（调用方回退直连播放）。
  Future<BiliStreamRegistration?> registerStreams({
    required String videoUrl,
    String? audioUrl,
    Map<String, String> headers = const {},
  }) async {
    final base = await start();
    if (base == null) return null;
    final seq = _seq++;
    final vKey = 'v$seq';
    final hasAudio = audioUrl != null && audioUrl.isNotEmpty;
    _streams[vKey] = _StreamEntry(videoUrl, headers);
    if (hasAudio) {
      _streams['a$seq'] = _StreamEntry(audioUrl, headers);
    }
    return BiliStreamRegistration(
      videoUrl: '$base/$vKey',
      audioUrl: hasAudio ? '$base/a$seq' : null,
    );
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final key = path.startsWith('/') ? path.substring(1) : path;
    final entry = _streams[key];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    HttpClientResponse? upstream;
    try {
      final request = await _client.getUrl(Uri.parse(entry.url));
      entry.headers.forEach((k, v) => request.headers.set(k, v));
      final range = req.headers.value('range');
      if (range != null && range.isNotEmpty) {
        request.headers.set('Range', range);
      }
      upstream = await request.close();

      final resp = req.response;
      resp.statusCode = upstream.statusCode;
      _copyHeader(upstream, resp, 'content-type');
      _copyHeader(upstream, resp, 'content-length');
      _copyHeader(upstream, resp, 'content-range');
      _copyHeader(upstream, resp, 'accept-ranges');
      await resp.addStream(upstream);
      await resp.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('Proxy error');
        await req.response.close();
      } catch (_) {}
    }
  }

  void _copyHeader(HttpClientResponse src, HttpResponse dst, String name) {
    final value = src.headers.value(name);
    if (value != null) dst.headers.set(name, value);
  }

  /// 停止代理并清空注册的流（播放结束 / 退出播放器时调用）。
  void stop() {
    _streams.clear();
    final server = _server;
    _server = null;
    _port = 0;
    if (server != null) {
      server.close(force: true);
    }
  }
}
