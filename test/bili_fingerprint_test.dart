import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/utils/bili_fingerprint_utils.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';

void main() {
  group('murmur3x64_128 / buvid_fp', () {
    test('空输入 + seed 0 → 0', () {
      expect(murmur3x64_128(const [], 0), BigInt.zero);
    });

    test('确定性：同输入同种子结果一致', () {
      final a = murmur3x64_128(utf8.encode('hello'), 31);
      final b = murmur3x64_128(utf8.encode('hello'), 31);
      expect(a, b);
    });

    test('不同种子结果不同', () {
      final a = murmur3x64_128(utf8.encode('hello'), 0);
      final b = murmur3x64_128(utf8.encode('hello'), 31);
      expect(a, isNot(b));
    });

    test('genBuvidFp 输出 32 位十六进制', () {
      final fp = genBuvidFp('Mozilla/5.0 test');
      expect(fp, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(fp), isTrue);
    });
  });

  group('本地指纹生成', () {
    test('genBiliUuid 格式：8-4-4-4-12 + 5位 + infoc', () {
      final uuid = genBiliUuid();
      expect(
        RegExp(r'^[1-9A-F]{8}-[1-9A-F]{4}-[1-9A-F]{4}-[1-9A-F]{4}-[1-9A-F]{12}\d{5}infoc$')
            .hasMatch(uuid),
        isTrue,
      );
    });

    test('genBLsid 格式：8 位十六进制 + _ + 时间戳十六进制', () {
      final lsid = genBLsid();
      expect(RegExp(r'^[0-9A-F]{8}_[0-9A-F]+$').hasMatch(lsid), isTrue);
    });

    test('randomDmImgStr 不含 % 且长度合理', () {
      final s = randomDmImgStr(16, 64);
      expect(s.contains('%'), isFalse);
      expect(s, isNotEmpty);
    });

    test('genDmImgParams 字段齐全', () {
      final p = genDmImgParams();
      expect(p['dm_img_list'], '[]');
      expect(p['dm_img_str'], isNotEmpty);
      expect(p['dm_cover_img_str'], isNotEmpty);
      expect(p['dm_img_inter'], isNotEmpty);
    });

    test('biliTicketHexsign 为 64 位十六进制', () {
      final h = biliTicketHexsign(1234567890);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });

    test('genExClimbWuzhiPayload 是 {"payload": "<json>"} 结构', () {
      final body = genExClimbWuzhiPayload();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect(decoded['payload'], isA<String>());
      final inner = jsonDecode(decoded['payload'] as String) as Map<String, dynamic>;
      expect(inner['3064'], 1);
      expect(inner['39c8'], '333.1387.fp.risk');
      expect((inner['3c43'] as Map)['adca'], 'Linux');
    });
  });

  group('合集链接解析', () {
    test('parseBiliSeasonListUrl 提取 mid + season_id', () {
      final ref = parseBiliSeasonListUrl(
        'https://space.bilibili.com/354656481/lists/2745051?type=season',
      );
      expect(ref, isNotNull);
      expect(ref!.mid, 354656481);
      expect(ref.seasonId, 2745051);
    });

    test('非合集链接返回 null', () {
      expect(parseBiliSeasonListUrl('https://www.bilibili.com/video/BV1xx411c7mD'), isNull);
      expect(parseBiliSeasonListUrl('hello'), isNull);
    });
  });

  group('合集模型解析', () {
    test('BiliUgcVideo.fromJson 解析 ugc_season 全集', () {
      final v = BiliUgcVideo.fromJson({
        'aid': 1,
        'bvid': 'BV1xx411c7mD',
        'title': '某视频',
        'pages': [
          {'cid': 100, 'page': 1, 'part': 'P1', 'duration': 60},
        ],
        'ugc_season': {
          'id': 888,
          'title': '某合集',
          'cover': 'https://cover',
          'sections': [
            {
              'id': 1,
              'title': '第一章',
              'episodes': [
                {
                  'aid': 2,
                  'bvid': 'BV2xx411c7mD',
                  'cid': 200,
                  'title': '第一集',
                  'arc': {'pic': 'https://pic', 'duration': 120},
                  'pages': [
                    {'cid': 201, 'page': 1, 'part': '上', 'duration': 60},
                    {'cid': 202, 'page': 2, 'part': '下', 'duration': 60},
                  ],
                },
                {
                  'aid': 3,
                  'bvid': 'BV3xx411c7mD',
                  'cid': 300,
                  'title': '第二集',
                  'arc': {'pic': 'https://pic2', 'duration': 90},
                },
              ],
            },
          ],
        },
      });
      expect(v.ugcSeason, isNotNull);
      expect(v.ugcSeason!.seasonId, 888);
      expect(v.ugcSeason!.title, '某合集');
      expect(v.ugcSeason!.sections.length, 1);
      final ep = v.ugcSeason!.sections.first.episodes;
      expect(ep.length, 2);
      expect(ep[0].bvid, 'BV2xx411c7mD');
      expect(ep[0].pages.length, 2);
      expect(ep[0].pages[1].cid, 202);
      expect(ep[0].durationMs, 120000);
      expect(ep[1].cid, 300);
    });

    test('无 ugc_season 时 ugcSeason 为 null', () {
      final v = BiliUgcVideo.fromJson({
        'aid': 1,
        'bvid': 'BV1xx411c7mD',
        'title': '普通视频',
        'pages': [
          {'cid': 100, 'page': 1, 'part': 'P1', 'duration': 60},
        ],
      });
      expect(v.ugcSeason, isNull);
      expect(v.pages.length, 1);
    });
  });
}
