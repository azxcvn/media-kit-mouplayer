import 'package:flutter/foundation.dart' show debugPrint;

import 'package:moumou/models/bilibili_user.dart';
import 'package:moumou/services/bilibili/bili_api.dart';
import 'package:moumou/services/bilibili/bili_constants.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/bili_app_sign.dart';
import 'package:moumou/utils/bili_wbi.dart';

/// 扫码登录二维码（TV 通道 auth_code 接口返回）。
class BiliQrCode {
  final String url;

  /// TV 扫码登录的 auth_code（轮询入参）。
  final String authCode;
  const BiliQrCode({required this.url, required this.authCode});
}

/// TV 扫码登录成功数据（直接来自 poll 响应 JSON，无需解析 Set-Cookie）。
class BiliTvLoginData {
  /// Web 通道凭证（SESSDATA / bili_jct / DedeUserID 等）。
  final Map<String, String> cookies;
  final String accessToken;
  final String refreshToken;

  const BiliTvLoginData({
    required this.cookies,
    required this.accessToken,
    required this.refreshToken,
  });
}

/// TV 扫码轮询结果：顶层 `code` 即状态码（0 成功 / 86101 未扫 / 86090 已扫 / 86038 失效）。
class BiliTvPoll {
  final int code;
  final String message;
  final BiliTvLoginData? data;
  const BiliTvPoll({required this.code, required this.message, this.data});

  bool get success => code == 0 && data != null;
}

/// 登录态自检（nav）结果。
class BiliNavData {
  final BiliUser user;

  /// WBI 密钥（从 nav 的 wbi_img 推导），非登录态也可能返回。
  final String mixinKey;

  const BiliNavData({required this.user, required this.mixinKey});
}

/// 哔哩哔哩认证服务：TV 扫码生成/轮询、登录态自检、buvid 预取、退出登录。
///
/// 扫码登录对齐 PiliPlus（`login.dart` getHDcode / codePoll，android_hd 通道 +
/// appSign）：凭证在 poll 响应 JSON 里直接返回（token_info + cookie_info.cookies），
/// 不依赖 Set-Cookie / 跨域跳转。
///
/// ⚠️ 曾按工作.md 第 7 点试改 Web 扫码（`/x/passport-login/web/qrcode/*`），
/// 真机验证失败后已回滚：Web 通道 poll 成功后返回的 `data.url` 是 ticket 换凭证的
/// crossDomain 链接，实测（2026-09）对非浏览器 HTTP 客户端**不下发** Set-Cookie
/// （302 跳转响应头为空），拿不到 SESSDATA；TV 通道凭证直接在 JSON 里，无此问题。
/// TV 通道已知限制：国际版哔哩哔哩客户端扫码后无法确认登录（轮询停在未确认）。
class BiliAuthService {
  BiliAuthService({BiliHttp? http}) : http = http ?? BiliHttp();

  final BiliHttp http;

  /// TV 通道登录请求头（对齐 PiliPlus `getHDcode`/`codePoll` 实际发出的头）。
  ///
  /// PiliPlus 的 TV 扫码请求走 `AnonymousAccount.headers`（=`Constants.baseHeaders`），
  /// 即 `app-key: android64` + `x-bili-aurora-zone: sh001`，**不是** `android_hd`。
  /// 若改发 `app-key: android_hd` + BiliDroid UA + `x-bili-trace-id`/`buvid` 等
  /// 「真 TV 端」头，会被风控按真机 TV 链路校验，国际版哔哩哔哩客户端扫码后无法
  /// 完成确认，轮询一直停在「未确认」导致登录失败。
  ///
  /// 其余通用头（Web UA / Referer / buvid3 / Content-Type）由 [BiliHttp.postFormRaw]
  /// 统一注入，无需在此重复。
  Map<String, String> _tvHeaders() => {
        'env': 'prod',
        'app-key': 'android64',
        'x-bili-aurora-zone': 'sh001',
      };

  /// 生成 TV 扫码二维码：POST `/x/passport-tv-login/qrcode/auth_code`。
  Future<BiliQrCode> generateTvQr() async {
    final params = <String, dynamic>{
      'local_id': '0',
      'platform': 'android',
      'mobi_app': 'android_hd',
    };
    biliAppSign(params, appKey: BiliConstants.tvAppKey, appSec: BiliConstants.tvAppSec);
    final resp = await http.postFormRaw(
      BiliApi.tvQrAuthCode,
      query: params.map((k, v) => MapEntry(k, v.toString())),
      headers: _tvHeaders(),
      withCookie: false,
    );
    final body = _data(resp);
    final url = body['url'] as String? ?? '';
    final authCode = body['auth_code'] as String? ?? '';
    if (url.isEmpty || authCode.isEmpty) {
      throw const BiliApiException('生成二维码失败：响应缺少 url/auth_code');
    }
    return BiliQrCode(url: url, authCode: authCode);
  }

  /// 轮询 TV 扫码状态：POST `/x/passport-tv-login/qrcode/poll`。
  Future<BiliTvPoll> pollTvQr(String authCode) async {
    final params = <String, dynamic>{'auth_code': authCode, 'local_id': '0'};
    biliAppSign(params, appKey: BiliConstants.tvAppKey, appSec: BiliConstants.tvAppSec);
    final resp = await http.postFormRaw(
      BiliApi.tvQrPoll,
      query: params.map((k, v) => MapEntry(k, v.toString())),
      headers: _tvHeaders(),
      withCookie: false,
    );
    final code = (resp['code'] as num?)?.toInt() ?? -1;
    final message = resp['message'] as String? ?? '';
    if (code != 0) {
      debugPrint(
        '[BILI-AUTH] poll 失败: code=$code message=$message data=${resp['data']}',
      );
    }
    BiliTvLoginData? loginData;
    if (code == 0) {
      final data = resp['data'];
      if (data is Map) {
        loginData = _parseTvLoginData(data);
        debugPrint(
          '[BILI-AUTH] poll 成功: '
          'hasSESSDATA=${loginData.cookies['SESSDATA']?.isNotEmpty == true} '
          'hasAccessToken=${loginData.accessToken.isNotEmpty}',
        );
      }
    }
    return BiliTvPoll(code: code, message: message, data: loginData);
  }

  /// 解析 TV 登录成功数据：token_info 的 access/refresh token + cookie_info 的 cookies。
  BiliTvLoginData _parseTvLoginData(Map data) {
    final cookies = <String, String>{};
    final cookieInfo = data['cookie_info'];
    if (cookieInfo is Map) {
      final list = cookieInfo['cookies'];
      if (list is List) {
        for (final c in list) {
          if (c is Map && c['name'] is String && c['value'] is String) {
            cookies[c['name'] as String] = c['value'] as String;
          }
        }
      }
    }
    final tokenInfo = data['token_info'];
    var access = '';
    var refresh = '';
    if (tokenInfo is Map) {
      access = tokenInfo['access_token'] as String? ?? '';
      refresh = tokenInfo['refresh_token'] as String? ?? '';
    }
    return BiliTvLoginData(
      cookies: cookies,
      accessToken: access,
      refreshToken: refresh,
    );
  }

  /// 登录态自检：`GET /x/web-interface/nav`（同时取 WBI 密钥）。
  ///
  /// 未登录时 nav 返回 `data.isLogin=false`（不抛异常），据此回落游客态。
  Future<BiliNavData> nav() async {
    final data = await http.getJson(BiliApi.nav);
    final body = _data(data);
    final user = BiliUser.fromJson(body);
    final vipLabel = body['vip_label'];
    debugPrint(
      '[BILI-AUTH] nav: isLogin=${body['isLogin']} vipStatus=${body['vipStatus']} '
      'vipType=${body['vipType']} vipLabelText='
      '${(vipLabel is Map && vipLabel['text'] is String) ? vipLabel['text'] : ''}',
    );
    String mixinKey = '';
    final wbiImg = body['wbi_img'];
    if (wbiImg is Map) {
      final imgUrl = (wbiImg['img_url'] as String?) ?? '';
      final subUrl = (wbiImg['sub_url'] as String?) ?? '';
      if (imgUrl.isNotEmpty && subUrl.isNotEmpty) {
        mixinKey = biliMixinKeyFromWbiImg(imgUrl, subUrl);
      }
    }
    return BiliNavData(user: user, mixinKey: mixinKey);
  }

  /// 预取设备指纹：`GET /x/frontend/finger/spi`，返回 (buvid3, buvid4)。
  Future<({String buvid3, String buvid4})> fetchBuvid() async {
    final data = await http.getJson(BiliApi.fingerSpi);
    final body = _data(data);
    return (
      buvid3: body['b_3'] as String? ?? '',
      buvid4: body['b_4'] as String? ?? '',
    );
  }

  /// 退出登录（POST，需 csrf）。
  Future<void> logout(String csrf) async {
    await http.postForm(BiliApi.logout, body: {'biliCSRF': csrf});
  }

  /// 取顶层 `data` 字段；缺失时抛异常（与业务 `code != 0` 一并视为失败）。
  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final code = (response['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final message = response['message'] as String? ?? '未知错误';
      throw BiliApiException(message.isEmpty ? '服务器返回错误（code=$code）' : message);
    }
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
