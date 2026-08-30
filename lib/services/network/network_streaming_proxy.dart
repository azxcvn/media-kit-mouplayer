/// 本地回环流代理：把远端文件转成 `127.0.0.1` 上的无凭据 loopback URL，
/// 供 mpv 播放（学习 mpvRx `NetworkStreamingProxy` 的思路）。
///
/// 每个注册流分配随机 capability token，凭据只存在于内存中、绝不进入 URL /
/// 播放列表 / 日志；token 可解析其下「兄弟路径」（HLS 分片等相对资源）。
/// 支持 GET / HEAD，处理 `Range` 分段请求与 seek。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:moumou/models/network_connection.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/services/network/network_client_factory.dart';
import 'package:moumou/utils/http_byte_range.dart';
import 'package:moumou/utils/network_mime_types.dart';
import 'package:moumou/utils/network_path.dart';

class NetworkStreamingProxy {
  /// 默认用真实工厂；测试可注入假客户端。
  final NetworkClient Function(NetworkConnection) clientFactory;

  NetworkStreamingProxy({NetworkClient Function(NetworkConnection)? clientFactory})
      : clientFactory = clientFactory ?? createNetworkClient;

  static final NetworkStreamingProxy instance = NetworkStreamingProxy();

  HttpServer? _server;
  final Map<String, _StreamEntry> _entries = {};
  final Random _random = Random.secure();

  /// 注册一个流并返回无凭据 loopback URL。
  Future<String> registerStream(
    NetworkConnection connection,
    String filePath, {
    int fileSize = -1,
    String mimeType = 'video/mp4',
  }) async {
    final server = await _ensureServer();
    final path = NetworkPath.from(filePath);
    final token = _generateToken();
    _entries[token] = _StreamEntry(
      connection: connection,
      primaryPath: path,
      fileSize: fileSize,
      mimeType: sanitizeMimeType(mimeType),
    );
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/$token${path.value}',
    );
    return uri.toString();
  }

  /// 返回指定 loopback URL 对应流自注册以来已传输的字节数。
  /// URL 无法解析、或不是本代理注册的流时返回 null。
  int? downloadedBytesForUrl(String url) => _entryFor(url)?.downloadedBytes;

  /// 返回指定 URL 对应流「最近 1 秒」的真实下载速率（字节/秒）。
  /// 滑动窗口统计代理层实际传给 mpv 的字节，稳定性优于周期性差分。
  double? recentSpeedBytesPerSec(String url) =>
      _entryFor(url)?.recentSpeedBytesPerSec();

  _StreamEntry? _entryFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return _entries[segments.first];
  }

  /// 释放指定 URL 对应的流（幂等）。
  Future<void> unregisterStream(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;
    final entry = _entries.remove(segments.first);
    if (entry == null) return;
    await _closeEntry(entry);
  }

  /// 关闭代理并释放所有流（测试 / 应用退出用）。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    final entries = _entries.values.toList();
    _entries.clear();
    for (final e in entries) {
      await _closeEntry(e);
    }
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server;
  }

  String _generateToken() {
    String token;
    do {
      final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
      token = base64Url.encode(bytes).replaceAll('=', '');
    } while (_entries.containsKey(token));
    return token;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final headOnly = request.method == 'HEAD';
    final route = _resolveToken(request);
    if (route == null) {
      await _text(response, HttpStatus.notFound, 'Stream not found', headOnly);
      return;
    }
    final (entry, path) = route;

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.headers.set('Allow', 'GET, HEAD');
      await _text(response, HttpStatus.methodNotAllowed, 'Method not allowed', headOnly);
      return;
    }

    try {
      final rangeHeader = request.headers.value('range');
      if (rangeHeader != null) {
        await _serveRangeMaybe(request, entry, path, rangeHeader);
      } else {
        await _serveFull(request, entry, path);
      }
    } catch (e) {
      // 不向响应泄露远端 URL、路径或异常细节；但记录到日志便于排查。
      print('[NetProxy] upstream 失败: $e');
      await _text(response, HttpStatus.internalServerError, 'Upstream stream failed', headOnly);
    }
  }

  /// 返回命中的 token → (entry, 规范化路径)；token 缺失返回 null。
  (_StreamEntry, NetworkPath)? _resolveToken(HttpRequest request) {
    final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final entry = _entries[segments.first];
    if (entry == null) return null;

    NetworkPath path;
    if (segments.length == 1) {
      path = entry.primaryPath;
    } else {
      try {
        path = NetworkPath.from('/${segments.sublist(1).join('/')}');
      } catch (_) {
        return null;
      }
    }
    return (entry, path);
  }

  Future<void> _serveFull(
    HttpRequest request,
    _StreamEntry entry,
    NetworkPath path,
  ) async {
    final headOnly = request.method == 'HEAD';
    final response = request.response;

    final size = await _fileSize(entry, path);
    final mime = _mimeTypeFor(entry, path);

    if (headOnly && size < 0) {
      await _text(response, HttpStatus.serviceUnavailable, 'Upstream size unavailable', true);
      return;
    }
    if (headOnly) {
      response.statusCode = HttpStatus.ok;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.contentType = _contentType(mime);
      response.headers.set('Content-Length', '$size');
      await response.close();
      return;
    }

    final stream = await _openOrNull(entry, path, 0);
    if (stream == null) {
      await _text(response, HttpStatus.serviceUnavailable, 'Upstream stream failed', false);
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.contentType = _contentType(mime);
    if (size >= 0) {
      response.contentLength = size;
    }
    try {
      await response.addStream(_countBytes(entry, stream));
      await response.close();
    } catch (e) {
      print('[NetProxy] 全量流 addStream 中断: $e');
      await response.close();
    }
  }

  Future<void> _serveRangeMaybe(
    HttpRequest request,
    _StreamEntry entry,
    NetworkPath path,
    String rangeHeader,
  ) async {
    final headOnly = request.method == 'HEAD';
    final response = request.response;
    final size = await _fileSize(entry, path);

    // 尺寸未知时无法分段：退化回完整流。
    if (size < 0) {
      await _serveFull(request, entry, path);
      return;
    }

    final range = HttpByteRange.parse(rangeHeader, size);
    if (range == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set('Content-Range', 'bytes */$size');
      response.headers.set('Accept-Ranges', 'bytes');
      await _text(response, HttpStatus.requestedRangeNotSatisfiable,
          'Requested range not satisfiable', headOnly,
          overrideStatus: true);
      return;
    }

    final mime = _mimeTypeFor(entry, path);
    response.statusCode = HttpStatus.partialContent;
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.set('Content-Range', 'bytes ${range.start}-${range.endInclusive}/$size');
    response.contentLength = range.length;
    response.headers.contentType = _contentType(mime);

    if (headOnly) {
      await response.close();
      return;
    }

    final stream = await _openOrNull(entry, path, range.start);
    if (stream == null) {
      await _text(response, HttpStatus.serviceUnavailable, 'Upstream stream failed', false);
      return;
    }
    try {
      await response.addStream(_countBytes(entry, _limitBytes(stream, range.length)));
      await response.close();
    } catch (e) {
      print('[NetProxy] 分段流 addStream 中断: $e');
      await response.close();
    }
  }

  Future<int> _fileSize(_StreamEntry entry, NetworkPath path) async {
    final known = entry.knownSizes[path];
    if (known != null) return known;
    final size = await _locked(entry, () async {
      try {
        final client = await _connectedClient(entry);
        return await client.getFileSize(path.value);
      } catch (e) {
        print('[NetProxy] getFileSize 失败: $e');
        return -1;
      }
    });
    if (size >= 0) entry.knownSizes[path] = size;
    return size;
  }

  Future<Stream<List<int>>?> _openOrNull(
    _StreamEntry entry,
    NetworkPath path,
    int offset,
  ) async {
    return _locked(entry, () async {
      try {
        final client = await _connectedClient(entry);
        return await client.openStream(path.value, offset: offset);
      } catch (e) {
        print('[NetProxy] openStream 失败: $e');
        return null;
      }
    });
  }

  Future<T> _locked<T>(_StreamEntry entry, Future<T> Function() action) async {
    final previous = entry.lock;
    final completer = Completer<void>();
    entry.lock = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<NetworkClient> _connectedClient(_StreamEntry entry) async {
    final existing = entry.client;
    if (existing != null && existing.isConnected()) return existing;
    final client = clientFactory(entry.connection);
    await client.connect();
    entry.client = client;
    return client;
  }

  String _mimeTypeFor(_StreamEntry entry, NetworkPath path) {
    if (path == entry.primaryPath) return entry.mimeType;
    return networkMimeTypeForFileName(path.relative) ?? 'application/octet-stream';
  }

  ContentType _contentType(String mime) {
    try {
      return ContentType.parse(mime);
    } catch (_) {
      return ContentType.binary;
    }
  }

  Future<void> _closeEntry(_StreamEntry entry) async {
    final client = entry.client;
    entry.client = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {
        // 忽略断开异常。
      }
    }
  }

  /// 记录每一笔回写给 mpv 的字节及其毫秒时间戳（累计字节 + 滑动窗口，供网速计算）。
  static Stream<List<int>> _countBytes(_StreamEntry entry, Stream<List<int>> source) {
    return source.map((chunk) {
      entry.downloadedBytes += chunk.length;
      entry._moments.add(
        _ByteMoment(DateTime.now().millisecondsSinceEpoch, chunk.length),
      );
      return chunk;
    });
  }

  static Stream<List<int>> _limitBytes(Stream<List<int>> source, int bytes) {
    var remaining = bytes;
    return source.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          if (remaining <= 0) {
            sink.close();
            return;
          }
          if (data.length <= remaining) {
            remaining -= data.length;
            sink.add(data);
          } else {
            sink.add(data.sublist(0, remaining));
            remaining = 0;
            sink.close();
          }
        },
        handleDone: (sink) => sink.close(),
      ),
    );
  }

  static Future<void> _text(
    HttpResponse response,
    int status,
    String message,
    bool headOnly, {
    bool overrideStatus = false,
  }) async {
    try {
      if (!overrideStatus) {
        response.statusCode = status;
      }
      final bytes = utf8.encode(message);
      response.headers.contentType = ContentType.text;
      if (!headOnly) {
        response.headers.set('Content-Length', '${bytes.length}');
        response.add(bytes);
      }
      await response.close();
    } catch (_) {
      // 响应可能已被客户端中止（mpv 断开），此时写入会抛 StreamSink is closed，忽略。
    }
  }

  static String sanitizeMimeType(String value) {
    final valid = RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+*-]+$');
    return valid.hasMatch(value) ? value : 'application/octet-stream';
  }
}

class _StreamEntry {
  final NetworkConnection connection;
  final NetworkPath primaryPath;
  int fileSize;
  final String mimeType;
  final Map<NetworkPath, int> knownSizes = {};
  NetworkClient? client;
  Future<void> lock = Future.value();
  int downloadedBytes = 0;

  /// 滑动窗口：最近约 1 秒内每笔 chunk 的（毫秒时间戳, 字节数），用于计算实时速率。
  final List<_ByteMoment> _moments = [];

  /// 最近 1 秒滑动窗口的真实下载速率（字节/秒）：
  /// 窗口内累计字节 ÷ 实际覆盖时长。下载连续时即「最近 1 秒平均速率」，
  /// 比周期性差分更抗「突发下载 + 采样瞬间错位」带来的抖动。
  double recentSpeedBytesPerSec() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 1000;
    _moments.removeWhere((m) => m.timeMs < cutoff);
    if (_moments.isEmpty) return 0;
    var bytes = 0;
    var earliest = now;
    for (final m in _moments) {
      bytes += m.bytes;
      if (m.timeMs < earliest) earliest = m.timeMs;
    }
    final spanMs = now - earliest;
    if (spanMs <= 0) return 0;
    return bytes / (spanMs / 1000.0);
  }

  _StreamEntry({
    required this.connection,
    required this.primaryPath,
    required this.fileSize,
    required this.mimeType,
  }) {
    if (fileSize >= 0) knownSizes[primaryPath] = fileSize;
  }
}

/// 一次数据块的传输记录（毫秒时间戳 + 字节数）。
class _ByteMoment {
  final int timeMs;
  final int bytes;
  _ByteMoment(this.timeMs, this.bytes);
}