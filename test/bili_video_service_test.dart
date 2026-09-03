import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/bili_video_service.dart';

void main() {
  Map<String, dynamic> pgcResp() => {
        'code': 0,
        'result': {
          'video_info': {
            'quality': 80,
            'timelength': 1423000,
            'accept_quality': [80, 64],
            'accept_description': ['1080P 高清', '720P 高清'],
            'dash': {
              'video': [
                {'id': 80, 'baseUrl': 'https://v80/', 'codecs': 'avc1.640032'},
              ],
              'audio': [
                {'id': 30280, 'baseUrl': 'https://a192/'},
              ],
            },
          },
        },
      };

  Map<String, dynamic> ugcResp() => {
        'code': 0,
        'data': {
          'quality': 64,
          'dash': {
            'video': [
              {'id': 64, 'baseUrl': 'https://v64/'},
            ],
            'audio': [
              {'id': 30280, 'baseUrl': 'https://a/'},
            ],
          },
        },
      };

  BiliVideoService serviceWith(http.Client client) => BiliVideoService(
        http: BiliHttp(client: client),
        mixinKeyProvider: () async => 'testmixin',
      );

  test('PGC playurl 解析 result.video_info 且带 WBI 签名', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/pgc/player/web/v2/playurl');
      expect(req.url.queryParameters['ep_id'], '100');
      expect(req.url.queryParameters['fnval'], '4048');
      expect(req.url.queryParameters.containsKey('w_rid'), isTrue);
      return http.Response(jsonEncode(pgcResp()), 200,
          headers: {'content-type': 'application/json'});
    });
    final r = await serviceWith(client).fetchPgcPlayUrl(epId: 100, cid: 200);
    expect(r.quality, 80);
    expect(r.defaultVideo!.baseUrl, 'https://v80/');
    expect(r.defaultAudio!.id, 30280);
  });

  test('UGC playurl 解析 data', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/x/player/wbi/playurl');
      expect(req.url.queryParameters['bvid'], 'BV1xx');
      return http.Response(jsonEncode(ugcResp()), 200,
          headers: {'content-type': 'application/json'});
    });
    final r = await serviceWith(client).fetchUgcPlayUrl(bvid: 'BV1xx', cid: 200);
    expect(r.quality, 64);
    expect(r.defaultVideo!.baseUrl, 'https://v64/');
  });

  test('resolveUgcVideo 取首分 P cid 与标题', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/x/web-interface/view');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'aid': 1,
            'bvid': 'BV1xx',
            'title': '标题',
            'pages': [
              {'cid': 555},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final v = await serviceWith(client).resolveUgcVideo('BV1xx');
    expect(v.cid, 555);
    expect(v.title, '标题');
  });

  test('错误码 -10403 抛大会员友好提示', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'code': -10403, 'message': 'xxx'}),
          200,
          headers: {'content-type': 'application/json'},
        ));
    expect(
      () => serviceWith(client).fetchPgcPlayUrl(epId: 1),
      throwsA(isA<BiliApiException>()
          .having((e) => e.message, 'message', '需要大会员权限')),
    );
  });

  test('WBI 密钥缺失时抛错', () async {
    final service = BiliVideoService(
      http: BiliHttp(client: MockClient((req) async => http.Response('{}', 200))),
      mixinKeyProvider: () async => '',
    );
    expect(
      () => service.fetchUgcPlayUrl(bvid: 'BV1xx', cid: 1),
      throwsA(isA<BiliApiException>()),
    );
  });
}
