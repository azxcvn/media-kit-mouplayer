import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';

/// 番剧（PGC）服务测试：用 MockClient 验证各端点请求参数与响应解析，
/// 以及搜索的 WBI 签名查询串。
void main() {
  BiliBangumiService serviceWith(MockClient client) => BiliBangumiService(
        http: BiliHttp(client: client),
        mixinKeyProvider: () async => 'testmixinkey',
      );

  http.Response jsonResponse(Map<String, dynamic> body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json'},
      );

  group('fetchCondition', () {
    test('请求参数 season_type/type=0 + 解析 filter', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'data': {
            'filter': [
              {
                'field': 'area',
                'name': '地区',
                'values': [
                  {'keyword': '-1', 'name': '全部'},
                  {'keyword': '2', 'name': '日本'},
                ],
              },
            ],
            'order': [
              {'field': '3', 'name': '最常追番', 'sort': '3'},
            ],
          },
        });
      }));

      final condition = await service.fetchCondition(1);
      expect(captured.queryParameters['season_type'], '1');
      expect(captured.queryParameters['type'], '0');
      expect(condition.filters.single.name, '地区');
      expect(condition.orders.single.field, '3');
    });
  });

  group('fetchIndex', () {
    test('season_type + type=0 + params 表 + 分页解析', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'data': {
            'has_next': 1,
            'list': [
              {'season_id': 1, 'title': 'A', 'badge': '独播'},
              {'season_id': 2, 'title': 'B'},
            ],
          },
        });
      }));

      final result = await service.fetchIndex(
        seasonType: 1,
        page: 2,
        params: {'order': '3', 'area': '2'},
      );
      expect(captured.queryParameters['season_type'], '1');
      expect(captured.queryParameters['type'], '0');
      expect(captured.queryParameters['page'], '2');
      expect(captured.queryParameters['pagesize'], '21');
      expect(captured.queryParameters['order'], '3');
      expect(captured.queryParameters['area'], '2');
      expect(result.hasNext, isTrue);
      expect(result.list.first.badge, '独播');
    });

    test('业务 code != 0 抛 BiliApiException', () async {
      final service = serviceWith(MockClient((request) async {
        return jsonResponse({'code': -404, 'message': '啥都木有'});
      }));
      expect(
        () => service.fetchIndex(seasonType: 1, page: 1),
        throwsA(isA<BiliApiException>()),
      );
    });
  });

  group('fetchRecommend', () {
    test('固定最常追番参数（st=1/order=3/type=1/pagesize=20）', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'data': {
            'has_next': 0,
            'list': [
              {'season_id': 1, 'title': 'A'},
            ],
          },
        });
      }));

      final result = await service.fetchRecommend(1);
      expect(captured.queryParameters['st'], '1');
      expect(captured.queryParameters['order'], '3');
      expect(captured.queryParameters['season_type'], '1');
      expect(captured.queryParameters['type'], '1');
      expect(captured.queryParameters['pagesize'], '20');
      expect(captured.queryParameters['area'], '-1');
      expect(result.list.length, 1);
    });
  });

  group('searchBangumi', () {
    test('WBI 签名查询串 + 结果解析', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'data': {
            'numResults': 1,
            'result': [
              {'season_id': 9, 'title': '<em class="keyword">巨人</em>'},
            ],
          },
        });
      }));

      final result = await service.searchBangumi('巨人');
      expect(captured.queryParameters['search_type'], 'media_bangumi');
      expect(captured.queryParameters['keyword'], '巨人');
      expect(captured.queryParameters['wts'], isNotEmpty);
      expect(captured.queryParameters['w_rid'], isNotEmpty);
      expect(result.list.single.title, '巨人');
    });

    test('无 mixinKey 抛异常', () async {
      final service = BiliBangumiService(
        http: BiliHttp(client: MockClient((_) async => jsonResponse({'code': 0}))),
        mixinKeyProvider: () async => '',
      );
      expect(() => service.searchBangumi('x'), throwsA(isA<BiliApiException>()));
    });
  });

  group('fetchSeasonDetail', () {
    test('season_id 请求 + result 解析', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'result': {
            'season_id': 10,
            'title': '某番剧',
            'episodes': [
              {'ep_id': 1, 'title': '第1话'},
            ],
          },
        });
      }));

      final detail = await service.fetchSeasonDetail(seasonId: 10);
      expect(captured.queryParameters['season_id'], '10');
      expect(captured.queryParameters.containsKey('ep_id'), isFalse);
      expect(detail.seasonId, 10);
    });

    test('ep_id 请求（链接解析直达）', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'result': {'season_id': 20, 'episodes': []},
        });
      }));

      final detail = await service.fetchSeasonDetail(epId: 55);
      expect(captured.queryParameters['ep_id'], '55');
      expect(captured.queryParameters.containsKey('season_id'), isFalse);
      expect(detail.seasonId, 20);
    });
  });

  group('fetchTimeline / fetchTimelineMerged', () {
    test('单条时间线：types/before/after + result 解析', () async {
      late Uri captured;
      final service = serviceWith(MockClient((request) async {
        captured = request.url;
        return jsonResponse({
          'code': 0,
          'result': [
            {
              'date': '09-01',
              'day_of_week': 3,
              'is_today': 1,
              'episodes': [
                {'episode_id': 1, 'season_id': 2, 'title': '某番'},
              ],
            },
          ],
        });
      }));

      final days = await service.fetchTimeline();
      expect(captured.queryParameters['types'], '1');
      expect(captured.queryParameters['before'], '6');
      expect(captured.queryParameters['after'], '6');
      expect(days.single.episodes.single.seasonId, 2);
    });

    test('合并番剧+国创：同日 episodes 拼接', () async {
      final service = serviceWith(MockClient((request) async {
        final types = request.url.queryParameters['types'];
        if (types == '1') {
          return jsonResponse({
            'code': 0,
            'result': [
              {
                'date': '09-01',
                'day_of_week': 3,
                'is_today': 0,
                'episodes': [
                  {'episode_id': 1, 'season_id': 2, 'title': '番剧A'},
                ],
              },
            ],
          });
        }
        return jsonResponse({
          'code': 0,
          'result': [
            {
              'date': '09-01',
              'day_of_week': 3,
              'is_today': 0,
              'episodes': [
                {'episode_id': 2, 'season_id': 3, 'title': '国创B'},
              ],
            },
          ],
        });
      }));

      final days = await service.fetchTimelineMerged();
      expect(days.length, 1);
      expect(days.single.episodes.length, 2);
      expect(days.single.episodes.map((e) => e.title), containsAll(['番剧A', '国创B']));
    });
  });
}
