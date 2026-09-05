import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:moumou/services/bilibili/bili_constants.dart';

/// 哔哩哔哩统一请求封装：Cookie / UA / Referer 注入 + UTF-8 解码 + 错误语义化。
///
/// 只负责传输层（网络错误 / 非 2xx 抛 [BiliApiException]）并返回解码后的 JSON
/// Map；业务 `code` 字段由各 service 自行解释（不同端点 code 语义不同，如
/// 扫码 poll 的状态码在顶层 `code`）。
///
/// [cookie] 与 [buvid3] 由 [BiliAccount] 在登录/预取后写入，请求时自动带入。
class BiliApiException implements Exception {
  final String message;
  const BiliApiException(this.message);

  @override
  String toString() => 'BiliApiException: $message';
}

class BiliHttp {
  BiliHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 当前登录 Cookie 串（`SESSDATA=..; bili_jct=..; DedeUserID=..`）。
  String? cookie;

  /// 设备指纹 Cookie 片段（`_uuid/buvid3/b_nut/b_lsid/buvid_fp/bili_ticket...`），
  /// 由 [BiliAccount] 在指纹初始化后写入，随每个请求合并进 `Cookie` 头。
  String? extraCookies;

  Map<String, String> _headers({
    bool withCookie = true,
    bool withReferer = true,
    bool jsonAccept = true,
  }) {
    final cookieParts = <String>[
      if (withCookie && cookie != null && cookie!.isNotEmpty) cookie!,
      if (extraCookies != null && extraCookies!.isNotEmpty) extraCookies!,
    ];
    return {
      'User-Agent': BiliConstants.webUserAgent,
      'Accept': jsonAccept ? 'application/json' : '*/*',
      if (withReferer) 'Referer': BiliConstants.referer,
      if (cookieParts.isNotEmpty) 'Cookie': cookieParts.join('; '),
    };
  }

  /// GET 请求，返回 UTF-8 解码后的 JSON Map（网络错误 / 非 2xx 抛异常）。
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? query,
    bool withCookie = true,
    bool withReferer = true,
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers(withCookie: withCookie, withReferer: withReferer))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// GET 请求，返回原始响应字节（弹幕等二进制响应用，不做 JSON 解码）。
  Future<Uint8List> getBytes(
    String url, {
    Map<String, String>? query,
    bool withCookie = true,
    bool withReferer = true,
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: _headers(
              withCookie: withCookie,
              withReferer: withReferer,
              jsonAccept: false,
            ),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BiliApiException('请求失败（HTTP ${response.statusCode}）');
    }
    return response.bodyBytes;
  }

  /// POST（表单编码）请求，返回 UTF-8 解码后的 JSON Map。
  Future<Map<String, dynamic>> postForm(
    String url, {
    Map<String, String>? body,
    bool withCookie = true,
    bool withReferer = true,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: {
              ..._headers(withCookie: withCookie, withReferer: withReferer),
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// POST（JSON 字符串 body）请求，返回 UTF-8 解码后的 JSON Map。
  ///
  /// 供 ExClimbWuzhi 等风控指纹接口使用（Content-Type: application/json）。
  Future<Map<String, dynamic>> postJson(
    String url, {
    required String body,
    bool withCookie = true,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: {
              ..._headers(withCookie: withCookie),
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// POST（参数走 **URL query**，无 body）请求，带完整默认头（Chrome UA + Referer + Cookie）。
  ///
  /// 供 GenWebTicket 使用：B23 用 httpx `client.request(POST, params=...)`，参数在
  /// query 字符串而非表单 body；放 body 会被服务端判 -400。
  Future<Map<String, dynamic>> postFormQuery(
    String url, {
    Map<String, String>? query,
    bool withCookie = true,
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: _headers(withCookie: withCookie))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// POST（表单编码，query 传参）请求，**不注入 Web UA / Referer / Accept**。
  ///
  /// 对齐 PiliPlus 的 TV 扫码请求（`Request().post(getTVCode, queryParameters:)`）：
  /// dio 默认 UA 是 `Dart/x (dart:io)`（非浏览器 UA）、无 Referer、只带
  /// `env/app-key/aurora-zone` 头 + buvid3 Cookie。B 站 TV auth_code 对「浏览器 UA」
  /// 与「非浏览器 UA」可能返回不同的扫码 URL，国际版客户端确认失败与此相关；
  /// 这里逐字节对齐 PiliPlus：dart:io 默认 UA + 自定义头 + 指纹 Cookie。
  Future<Map<String, dynamic>> postFormTv(
    String url, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              ...?headers,
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
              if (extraCookies != null && extraCookies!.isNotEmpty)
                'Cookie': extraCookies!,
            },
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BiliApiException('网络请求失败: $e');
    }
    return _decode(response);
  }

  /// 统一响应解码：非 2xx 抛异常；JSON 解码失败抛异常；返回 Map。
  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BiliApiException('请求失败（HTTP ${response.statusCode}）');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw BiliApiException('响应不是 JSON 对象');
    } catch (e) {
      if (e is BiliApiException) rethrow;
      throw BiliApiException('响应解析失败: $e');
    }
  }
}
