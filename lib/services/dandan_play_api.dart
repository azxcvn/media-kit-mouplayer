/// 弹弹Play 开放弹幕网络 API 客户端（签名验证模式）。
///
/// 封装搜索 / 拉取弹幕 / 文件匹配三个公开接口，统一处理：
/// - 请求头（X-AppId / X-Timestamp / X-Signature，签名算法见
///   `utils/dandan_signature.dart`）；
/// - 响应体按 UTF-8 解码（不依赖 Content-Type 的 charset）；
/// - 非 200 / 业务错误（success=false）抛出 [DandanApiException]。
///
/// 自建服务器通过 [baseUrl] 参数指定（默认官方地址）；密钥读取自
/// `dandan_play_keys.dart`（gitignored 私有文件）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/services/dandan_play_keys.dart';
import 'package:moumou/utils/dandan_signature.dart';

/// API 请求失败异常（网络错误 / 非 200 / 业务错误统一抛出）
class DandanApiException implements Exception {
  final String message;
  const DandanApiException(this.message);

  @override
  String toString() => 'DandanApiException: $message';
}

class DandanPlayApi {
  DandanPlayApi({http.Client? client}) : _client = client ?? http.Client();

  static const String defaultBaseUrl = 'https://api.dandanplay.net';

  final http.Client _client;

  /// 解析实际请求地址：自建服务器优先，无 scheme 视为非法回退官方。
  String _resolveBase(String? baseUrl) {
    final url = baseUrl?.trim();
    if (url == null || url.isEmpty) return defaultBaseUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw DandanApiException('服务器地址无效（需以 http/https 开头）: $url');
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 生成签名请求头（时间戳取当前 UTC 秒）
  Map<String, String> _authHeaders(String path) {
    final timestamp =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return {
      'X-AppId': kDandanPlayAppId,
      'X-Timestamp': '$timestamp',
      'X-Signature': dandanSignature(
        appId: kDandanPlayAppId,
        timestamp: timestamp,
        path: path,
        appSecret: kDandanPlayAppSecret,
      ),
    };
  }

  /// GET 请求，返回 UTF-8 解码后的响应体文本（非 200 抛异常）。
  Future<String> _get(String url, String path) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: {'Accept': 'application/json', ..._authHeaders(path)})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw DandanApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// POST 请求（JSON），返回 UTF-8 解码后的响应体文本（非 200 抛异常）。
  Future<String> _post(String url, String path, Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ..._authHeaders(path),
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw DandanApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// 统一响应解码：非 2xx 或业务 success=false 抛 [DandanApiException]。
  String _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DandanApiException('请求失败（HTTP ${response.statusCode}）');
    }
    // 业务错误：{ "success": false, "errorCode": .., "errorMessage": .. }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['success'] == false) {
        final msg = decoded['errorMessage'];
        throw DandanApiException(msg is String && msg.isNotEmpty ? msg : '服务器返回错误');
      }
    } catch (e) {
      if (e is DandanApiException) rethrow;
      // 非 JSON 响应按成功文本返回
    }
    return text;
  }

  /// 搜索番剧：GET /api/v2/search/episodes?anime=KEYWORD
  Future<List<DandanAnime>> searchAnime(
    String keyword, {
    String? baseUrl,
  }) async {
    final path = '/api/v2/search/episodes';
    final url =
        '${_resolveBase(baseUrl)}$path?anime=${Uri.encodeQueryComponent(keyword)}';
    final text = await _get(url, path);
    final decoded = jsonDecode(text);
    if (decoded is! Map) return const [];
    final raw = decoded['animes'];
    if (raw is! List) return const [];
    final result = <DandanAnime>[];
    for (final item in raw) {
      if (item is Map) {
        final anime = DandanAnime.fromJson(item.cast<String, dynamic>());
        if (anime != null) result.add(anime);
      }
    }
    return result;
  }

  /// 拉取单集弹幕：GET /api/v2/comment/{episodeId}?withRelated=true
  Future<List<DandanComment>> getComments(
    int episodeId, {
    String? baseUrl,
  }) async {
    final path = '/api/v2/comment/$episodeId';
    final url = '${_resolveBase(baseUrl)}$path?withRelated=true';
    final text = await _get(url, path);
    final decoded = jsonDecode(text);
    if (decoded is! Map) return const [];
    final raw = decoded['comments'];
    if (raw is! List) return const [];
    final result = <DandanComment>[];
    for (final item in raw) {
      if (item is Map) {
        final comment = DandanComment.fromJson(item.cast<String, dynamic>());
        if (comment != null) result.add(comment);
      }
    }
    return result;
  }

  /// 文件匹配：POST /api/v2/match（文件前 16MB 的 MD5 + 文件名 + 大小）。
  Future<List<DandanMatchInfo>> matchDanmaku({
    required String fileName,
    required String fileHash,
    required int fileSize,
    String? baseUrl,
  }) async {
    final path = '/api/v2/match';
    final url = _resolveBase(baseUrl) + path;
    final text = await _post(url, path, {
      'fileName': fileName,
      'fileHash': fileHash,
      'fileSize': fileSize,
    });
    final decoded = jsonDecode(text);
    if (decoded is! Map) return const [];
    if (decoded['isMatched'] != true) return const [];
    final raw = decoded['matches'];
    if (raw is! List) return const [];
    final result = <DandanMatchInfo>[];
    for (final item in raw) {
      if (item is Map) {
        final match = DandanMatchInfo.fromJson(item.cast<String, dynamic>());
        if (match != null) result.add(match);
      }
    }
    return result;
  }
}
