import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/services/bilibili/bili_auth_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';

/// TV 扫码登录服务测试（对齐 PiliPlus getHDcode/codePoll，凭证直接在 poll JSON 里）。
void main() {
  BiliAuthService serviceWith(http.Client client) =>
      BiliAuthService(http: BiliHttp(client: client));

  test('generateTvQr 解析 url + auth_code，且带 appSign 参数', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/x/passport-tv-login/qrcode/auth_code');
      // appSign 注入的 appkey / ts / sign 走 query
      expect(req.url.queryParameters['appkey'], isNotEmpty);
      expect(req.url.queryParameters['ts'], isNotNull);
      expect(req.url.queryParameters['sign'], isNotEmpty);
      expect(req.url.queryParameters['mobi_app'], 'android_hd');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'url': 'https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth?auth_code=abc',
            'auth_code': 'abc',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final qr = await serviceWith(client).generateTvQr();
    expect(qr.url, isNotEmpty);
    expect(qr.authCode, 'abc');
  });

  test('pollTvQr 成功：从 token_info + cookie_info.cookies 解析凭证', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/x/passport-tv-login/qrcode/poll');
      expect(req.url.queryParameters['auth_code'], 'abc');
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': '0',
          'data': {
            'is_new': false,
            'mid': 10086,
            'token_info': {
              'access_token': 'at123',
              'refresh_token': 'rt456',
            },
            'cookie_info': {
              'cookies': [
                {'name': 'SESSDATA', 'value': 'abc,123,def'},
                {'name': 'bili_jct', 'value': 'xyz'},
                {'name': 'DedeUserID', 'value': '42'},
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final poll = await serviceWith(client).pollTvQr('abc');
    expect(poll.success, isTrue);
    expect(poll.code, 0);
    expect(poll.data, isNotNull);
    expect(poll.data!.cookies['SESSDATA'], 'abc,123,def');
    expect(poll.data!.cookies['bili_jct'], 'xyz');
    expect(poll.data!.cookies['DedeUserID'], '42');
    expect(poll.data!.accessToken, 'at123');
    expect(poll.data!.refreshToken, 'rt456');
  });

  test('pollTvQr 未扫码：顶层 code=86101 且 data 为空', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({'code': 86101, 'message': '未扫码', 'data': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final poll = await serviceWith(client).pollTvQr('abc');
    expect(poll.success, isFalse);
    expect(poll.code, 86101);
    expect(poll.data, isNull);
  });

  test('pollTvQr 已扫码未确认：顶层 code=86090', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({'code': 86090, 'message': '二维码已扫码未确认', 'data': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final poll = await serviceWith(client).pollTvQr('abc');
    expect(poll.code, 86090);
    expect(poll.data, isNull);
  });

  test('pollTvQr 成功但 cookie_info 缺失 → data 凭证为空（页面提示重试，不冻结）', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {'token_info': null, 'cookie_info': null},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final poll = await serviceWith(client).pollTvQr('abc');
    expect(poll.code, 0);
    // 凭证对象仍返回（cookies 为空）；completeQrLogin 会因缺少 SESSDATA 抛错，
    // 页面走「登录失败，请重试」+ 刷新（不静默冻结）。
    expect(poll.data, isNotNull);
    expect(poll.data!.cookies['SESSDATA'], isNull);
    expect(poll.data!.accessToken, isEmpty);
  });
}
