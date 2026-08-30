/// WebDAV 客户端（基于 `package:http`，纯 Dart 实现）。
///
/// 学习 mpvRx `WebDavClient` 的分层思路：
/// 1. URL 由解码后的路径段拼接，凭据/保留字符不进 URL；
/// 2. 列表用 PROPFIND `Depth: 1`；连接自检用 `Depth: 0`；
/// 3. 流式读取用 GET，带偏移时发 `Range` 并校验 206 + Content-Range 起点，
///    服务器忽略 Range（返回 200）时直接报错而非返回损坏的偏移流。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:moumou/models/network_connection.dart';
import 'package:moumou/models/network_file.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/utils/network_mime_types.dart';
import 'package:moumou/utils/network_path.dart';
import 'package:moumou/utils/webdav_xml.dart';

class WebDavClient implements NetworkClient {
  final NetworkConnection connection;

  WebDavClient(this.connection);

  http.Client? _client;
  bool _connected = false;

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>';

  static final _contentRangePattern = RegExp(
    r'bytes\s+(\d+)-(\d+)/(\d+|\*)',
    caseSensitive: false,
  );

  /// 去掉路径末尾的一个或多个 `/`（`/movies/` → `/movies`）。
  static String _trimTrailingSlash(String path) =>
      path.replaceAll(RegExp(r'/+$'), '');

  /// 提取 href 中的路径部分：去掉可能的 `scheme://host[:port]` 前缀
  /// （部分 WebDAV 服务器返回绝对 URL，而非以 `/` 开头的相对路径）。
  static String _pathOnly(String href) {
    final schemeEnd = href.indexOf('://');
    if (schemeEnd < 0) return href;
    final rest = href.substring(schemeEnd + 3);
    final slash = rest.indexOf('/');
    return slash < 0 ? '/' : rest.substring(slash);
  }

  @override
  bool isConnected() => _connected;

  @override
  Future<void> connect() async {
    _client ??= http.Client();
    // Depth 0 自检：能拿到 2xx 即视为可达且凭据有效。
    await _propfind(_uri('/', trailingSlash: true), depth: 0);
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    final client = _client;
    _client = null;
    client?.close();
  }

  @override
  Future<List<NetworkFile>> listFiles(String path) async {
    final directory = NetworkPath.from(path);
    final dirUri = _uri(directory.value, trailingSlash: true);
    // 自身条目 = 目录自身的服务端路径（百分号解码、去尾部斜杠、去 scheme 前缀）。
    // dirUri.path 是 URI 编码态，而 resource.href 已被 percentDecode 解码；
    // 若直接比较，中文 / 空格等字符的编码不一致会导致自身条目漏滤，
    // 「幽灵文件夹」随之出现，点击即 404。故两侧统一到「解码后的路径」再比。
    final selfPath = _trimTrailingSlash(percentDecode(dirUri.path));

    final body = await _propfind(dirUri, depth: 1);
    final files = <NetworkFile>[];
    for (final resource in parseWebDavMultistatus(body)) {
      if (_trimTrailingSlash(_pathOnly(resource.href)) == selfPath) continue;
      final filePath = _childOrNull(directory, resource.name);
      if (filePath == null) continue;
      files.add(
        NetworkFile(
          name: resource.name,
          path: filePath,
          isDirectory: resource.isDirectory,
          size: resource.isDirectory ? -1 : resource.contentLength,
          lastModified: resource.lastModifiedMs,
          mimeType: resource.isDirectory
              ? null
              : networkMimeTypeForFileName(resource.name),
        ),
      );
    }
    return files;
  }

  @override
  Future<int> getFileSize(String path) async {
    final filePath = NetworkPath.from(path);
    final body = await _propfind(_uri(filePath.value), depth: 0);
    final resources = parseWebDavMultistatus(body);
    if (resources.isEmpty) {
      throw const NetworkClientException('文件不存在或不是文件');
    }
    final resource = resources.first;
    if (resource.isDirectory) {
      throw const NetworkClientException('目标是一个目录');
    }
    return resource.contentLength;
  }

  @override
  Future<Stream<List<int>>> openStream(String path, {int offset = 0}) async {
    final client = _client ??= http.Client();
    final request = http.Request('GET', _uri(NetworkPath.from(path).value));
    request.headers['Authorization'] = _authHeader();
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';

    final response = await client.send(request);
    if (offset > 0) {
      if (response.statusCode != 206) {
        await _drain(response);
        throw NetworkClientException(
          response.statusCode == 200
              ? '服务器忽略了分段请求，无法精确跳转'
              : '分段请求失败（HTTP ${response.statusCode}）',
        );
      }
      final contentRange = response.headers['content-range'] ?? '';
      final start = _contentRangePattern
          .firstMatch(contentRange)
          ?.group(1);
      if (start == null || int.parse(start) != offset) {
        await _drain(response);
        throw const NetworkClientException('服务器返回的分段起点与请求不一致');
      }
    } else if (response.statusCode < 200 || response.statusCode >= 300) {
      await _drain(response);
      throw NetworkClientException(
        '下载失败（HTTP ${response.statusCode}'
        '${response.statusCode == 401 ? '，认证失败' : ''}）',
      );
    }
    return response.stream;
  }

  /// 拼接连接根 + 相对路径为完整 URL（解码后的段，由 [Uri] 统一编码）。
  Uri _uri(String relativePath, {bool trailingSlash = false}) {
    final base = NetworkPath.from(connection.path);
    final rel = NetworkPath.from(relativePath);
    final segments = <String>[...base.segments, ...rel.segments];
    if (trailingSlash) segments.add('');
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}';
    return Uri(
      scheme: connection.useHttps ? 'https' : 'http',
      host: connection.host,
      port: connection.port,
      path: path,
    );
  }

  String _authHeader() =>
      'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}';

  Future<String> _propfind(Uri uri, {required int depth}) async {
    final client = _client ??= http.Client();
    final request = http.Request('PROPFIND', uri);
    request.headers['Authorization'] = _authHeader();
    request.headers['Depth'] = '$depth';
    request.headers['Content-Type'] = 'application/xml; charset="utf-8"';
    request.body = _propfindBody;

    final response = await client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NetworkClientException(
        'WebDAV 请求失败（HTTP ${response.statusCode}'
        '${response.statusCode == 401 ? '，认证失败' : ''}）',
      );
    }
    return body;
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } catch (_) {
      // 忽略丢弃过程中的异常。
    }
  }

  static String? _childOrNull(NetworkPath dir, String name) {
    try {
      return dir.child(name).value;
    } catch (_) {
      return null; // 含非法分隔符的名称跳过
    }
  }
}