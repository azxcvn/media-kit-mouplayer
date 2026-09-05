import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';

/// 番剧（PGC）数据模型 + 链接解析纯函数测试。
void main() {
  group('BiliIndexItem.fromJson', () {
    test('正常解析', () {
      final item = BiliIndexItem.fromJson({
        'season_id': 12345,
        'title': '某番剧',
        'cover': 'https://example.com/cover.jpg',
        'index_show': '全13话',
        'badge': '独播',
        'order': '更新至第5话',
      });
      expect(item.seasonId, 12345);
      expect(item.title, '某番剧');
      expect(item.indexShow, '全13话');
      expect(item.badge, '独播');
      expect(item.order, '更新至第5话');
    });

    test('字段缺失回退默认值', () {
      final item = BiliIndexItem.fromJson(const {});
      expect(item.seasonId, 0);
      expect(item.title, '');
      expect(item.cover, '');
      expect(item.order, '');
    });

    test('数字字段以字符串下发也能解析（防类型转换崩溃）', () {
      final item = BiliIndexItem.fromJson({'season_id': '88', 'title': 'A'});
      expect(item.seasonId, 88);
    });
  });

  group('BiliIndexResult.fromJson', () {
    test('has_next int → bool + 列表', () {
      final r = BiliIndexResult.fromJson({
        'has_next': 1,
        'list': [
          {'season_id': 1, 'title': 'A'},
          {'season_id': 2, 'title': 'B'},
          'bad',
        ],
      });
      expect(r.hasNext, isTrue);
      expect(r.list.length, 2);
    });

    test('has_next 为字符串也能解析', () {
      final r = BiliIndexResult.fromJson({'has_next': '0', 'list': []});
      expect(r.hasNext, isFalse);
    });
  });

  group('BiliIndexCondition.fromJson', () {
    test('filter / order 解析', () {
      final c = BiliIndexCondition.fromJson({
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
      });
      expect(c.filters.length, 1);
      expect(c.filters.first.field, 'area');
      expect(c.filters.first.values.first.keyword, '-1');
      expect(c.orders.first.field, '3');
      expect(c.orders.first.name, '最常追番');
    });
  });

  group('BiliSearchItem.fromJson', () {
    test('剥离 <em> 高亮 + media_score 解析', () {
      final item = BiliSearchItem.fromJson({
        'season_id': 7,
        'media_id': 8,
        'title': '<em class="keyword">进击的巨人</em> 最终季',
        'cover': 'https://example.com/c.jpg',
        'media_score': {'score': 9.8, 'user_count': 123},
        'areas': '日本',
      });
      expect(item.seasonId, 7);
      expect(item.mediaId, 8);
      expect(item.title, '进击的巨人 最终季');
      expect(item.mediaScore, 9.8);
    });
  });

  group('BiliEpisode', () {
    test('fromJson 字段映射', () {
      final ep = BiliEpisode.fromJson({
        'ep_id': 100,
        'aid': 200,
        'cid': 300,
        'bvid': 'BV1xx411c7mD',
        'title': '第1话',
        'long_title': '第1话 开端',
        'duration': 1423000,
        'badge': '会员',
        'status': 2,
      });
      expect(ep.epId, 100);
      expect(ep.cid, 300);
      expect(ep.longTitle, '第1话 开端');
      expect(ep.badge, '会员');
    });
  });

  group('BiliSeasonDetail.fromJson', () {
    test('完整解析（标题/评分/统计/更新/选集/多季）', () {
      final d = BiliSeasonDetail.fromJson({
        'season_id': 10,
        'title': '紫罗兰永恒花园',
        'cover': 'https://example.com/s.jpg',
        'evaluate': '简介内容',
        'areas': [
          {'id': 2, 'name': '日本'},
        ],
        'rating': {'score': 9.8},
        'publish': {'pub_time_show': '2018-01-10'},
        'stat': {
          'views': 120000,
          'danmakus': 8888,
          'favorite': 50000,
          'likes': 12000,
          'coins': 3000,
        },
        'new_ep': {'title': '13', 'desc': '全13话'},
        'episodes': [
          {'ep_id': 1, 'title': '第1话', 'long_title': '第1话 你即将死去'},
          {'ep_id': 2, 'title': '第2话'},
        ],
        'seasons': [
          {'season_id': 10, 'season_title': '第一季'},
        ],
      });
      expect(d.seasonId, 10);
      expect(d.title, '紫罗兰永恒花园');
      expect(d.ratingScore, 9.8);
      expect(d.areas, ['日本']);
      expect(d.views, 120000);
      expect(d.danmaku, 8888);
      expect(d.favorite, 50000);
      expect(d.likes, 12000);
      expect(d.coins, 3000);
      expect(d.newEpDesc, '全13话');
      expect(d.episodes.length, 2);
      expect(d.episodes.first.longTitle, '第1话 你即将死去');
      expect(d.seasons.length, 1);
    });
  });

  group('BiliTimelineDay.fromJson', () {
    test('日期/星期/今天 + episodes + follow', () {
      final day = BiliTimelineDay.fromJson({
        'date': '09-01',
        'day_of_week': 3,
        'is_today': 1,
        'episodes': [
          {'episode_id': 1, 'season_id': 2, 'title': '某番', 'pub_index': '第5话', 'follow': 1},
        ],
      });
      expect(day.date, '09-01');
      expect(day.dayOfWeek, 3);
      expect(day.isToday, isTrue);
      expect(day.episodes.single.seasonId, 2);
      expect(day.episodes.single.follow, 1);
    });
  });

  group('parseBiliBangumiUrl', () {
    test('ss 链接', () {
      final ref = parseBiliBangumiUrl('https://www.bilibili.com/bangumi/play/ss12345');
      expect(ref, isNotNull);
      expect(ref!.hasSeason, isTrue);
      expect(ref.seasonId, 12345);
    });

    test('ep 链接', () {
      final ref = parseBiliBangumiUrl('https://www.bilibili.com/bangumi/play/ep67890');
      expect(ref, isNotNull);
      expect(ref!.hasEpisode, isTrue);
      expect(ref.epId, 67890);
    });

    test('BV 号（UGC）', () {
      final ref = parseBiliBangumiUrl('https://www.bilibili.com/video/BV1xx411c7mD');
      expect(ref, isNotNull);
      expect(ref!.isUgc, isTrue);
      expect(ref.bvid, 'BV1xx411c7mD');
    });

    test('av 号（UGC，工作.md 第 8 点）', () {
      final ref = parseBiliBangumiUrl('https://www.bilibili.com/video/av170001');
      expect(ref, isNotNull);
      expect(ref!.isUgc, isTrue);
      expect(ref.hasAid, isTrue);
      expect(ref.aid, 170001);
    });

    test('同时含 ss 与 ep 优先取 ss', () {
      final ref = parseBiliBangumiUrl('xx/ss111/ep222');
      expect(ref, isNotNull);
      expect(ref!.hasSeason, isTrue);
      expect(ref.seasonId, 111);
    });

    test('无法识别返回 null', () {
      expect(parseBiliBangumiUrl('hello world'), isNull);
      expect(parseBiliBangumiUrl(''), isNull);
    });
  });
}
