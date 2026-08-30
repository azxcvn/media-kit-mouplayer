import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/dandan_models.dart';

/// 弹弹Play API 数据模型 fromJson 测试（容错 + 字段映射）。
void main() {
  group('DandanEpisode.fromJson', () {
    test('正常解析', () {
      final ep = DandanEpisode.fromJson({
        'episodeId': 42,
        'episodeTitle': '第42话',
      });
      expect(ep, isNotNull);
      expect(ep!.episodeId, 42);
      expect(ep.episodeTitle, '第42话');
    });

    test('字段缺失/类型不符 → null', () {
      expect(DandanEpisode.fromJson({'episodeTitle': 'x'}), isNull);
      expect(DandanEpisode.fromJson({'episodeId': '42', 'episodeTitle': 'x'}),
          isNull);
    });
  });

  group('DandanAnime.fromJson', () {
    test('解析番剧 + 集列表（坏集跳过）', () {
      final anime = DandanAnime.fromJson({
        'animeId': 1,
        'animeTitle': '某番剧',
        'type': 'tv',
        'typeDescription': 'TV',
        'episodes': [
          {'episodeId': 1, 'episodeTitle': '第01话'},
          {'episodeTitle': '缺 id'},
          {'episodeId': 2, 'episodeTitle': '第02话'},
        ],
      });
      expect(anime, isNotNull);
      expect(anime!.animeId, 1);
      expect(anime.animeTitle, '某番剧');
      expect(anime.episodes.length, 2);
      expect(anime.episodes.map((e) => e.episodeId).toList(), [1, 2]);
    });

    test('缺 animeId/animeTitle → null', () {
      expect(DandanAnime.fromJson({'animeTitle': 'x'}), isNull);
      expect(DandanAnime.fromJson({'animeId': 1}), isNull);
    });
  });

  group('DandanMatchInfo.fromJson', () {
    test('正常解析（含 shift 默认 0）', () {
      final m = DandanMatchInfo.fromJson({
        'episodeId': 7,
        'animeId': 8,
        'animeTitle': '番剧',
        'episodeTitle': '第07话',
        'type': 'tv',
        'typeDescription': 'TV',
      });
      expect(m, isNotNull);
      expect(m!.episodeId, 7);
      expect(m.shift, 0);
    });

    test('shift 数值解析', () {
      final m = DandanMatchInfo.fromJson({
        'episodeId': 7,
        'animeId': 8,
        'animeTitle': 'a',
        'episodeTitle': 'b',
        'shift': 1.5,
      });
      expect(m!.shift, 1.5);
    });

    test('缺关键字段 → null', () {
      expect(DandanMatchInfo.fromJson({'episodeId': 7}), isNull);
    });
  });
}
