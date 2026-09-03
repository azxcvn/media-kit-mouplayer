import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/bili_dash.dart';

void main() {
  Map<String, dynamic> dashJson() => {
        'quality': 80,
        'format': 'flv',
        'timelength': 1423000,
        'accept_description': ['1080P 高清', '720P 高清', '480P 清晰'],
        'accept_quality': [80, 64, 32],
        'dash': {
          'duration': 1423,
          'video': [
            {
              'id': 80,
              'baseUrl': 'https://v80.example/',
              'backupUrl': ['https://v80b.example/'],
              'bandwidth': 2000000,
              'mimeType': 'video/mp4',
              'codecs': 'avc1.640032',
              'width': 1920,
              'height': 1080,
              'frameRate': '16000/656',
            },
            {
              'id': 64,
              'base_url': 'https://v64.example/',
              'bandwidth': 1000000,
              'codecs': 'avc1.640028',
              'width': 1280,
              'height': 720,
            },
          ],
          'audio': [
            {
              'id': 30280,
              'baseUrl': 'https://a192.example/',
              'bandwidth': 320000,
              'codecs': 'mp4a.40.2',
            },
            {
              'id': 30232,
              'baseUrl': 'https://a132.example/',
              'bandwidth': 220000,
            },
          ],
        },
        'clip_info_list': [
          {'start': 0.0, 'end': 90.0, 'clipType': 'CLIP_TYPE_OP'},
          {'start': 1400.0, 'end': 1423.0, 'clipType': 'CLIP_TYPE_ED'},
        ],
      };

  test('解析 DASH 结果与默认选流', () {
    final r = BiliPlayUrlResult.fromJson(dashJson());
    expect(r.quality, 80);
    expect(r.timelength, 1423000);
    expect(r.acceptQuality, [80, 64, 32]);
    expect(r.acceptDescription, ['1080P 高清', '720P 高清', '480P 清晰']);
    expect(r.videos.length, 2);
    expect(r.defaultVideo!.id, 80);
    // base_url 兼容
    expect(r.videos[1].baseUrl, 'https://v64.example/');
    // 默认音频优先 30280（192K）
    expect(r.defaultAudio!.id, 30280);
    // clips 映射
    expect(r.clips.length, 2);
    expect(r.clips[0].isOp, isTrue);
    expect(r.clips[1].isEd, isTrue);
  });

  test('qualityOptions 按下标对齐 qn 与描述', () {
    final r = BiliPlayUrlResult.fromJson(dashJson());
    final opts = r.qualityOptions;
    expect(opts.length, 3);
    expect(opts[0].qn, 80);
    expect(opts[0].description, '1080P 高清');
    expect(opts[2].qn, 32);
  });

  test('baseUrls 对象数组格式', () {
    final json = {
      'quality': 80,
      'dash': {
        'video': [
          {
            'id': 80,
            'baseUrls': [
              {
                'base_url': 'https://primary/',
                'backup_url': ['https://backup/'],
              },
            ],
          },
        ],
      },
    };
    final r = BiliPlayUrlResult.fromJson(json);
    expect(r.videos.single.baseUrl, 'https://primary/');
    expect(r.videos.single.backupUrls, ['https://backup/']);
  });

  test('baseUrls 字符串数组格式', () {
    final json = {
      'quality': 64,
      'dash': {
        'video': [
          {'id': 64, 'baseUrls': ['https://a/', 'https://b/']},
        ],
      },
    };
    final r = BiliPlayUrlResult.fromJson(json);
    expect(r.videos.single.baseUrl, 'https://a/');
    expect(r.videos.single.backupUrls, ['https://b/']);
  });

  test('数字字段为字符串时防御式解析', () {
    final json = {
      'quality': '80',
      'timelength': '1423000',
      'accept_quality': ['80', '64'],
      'dash': {
        'video': [
          {'id': '80', 'baseUrl': 'https://v/', 'width': '1920'},
        ],
        'audio': [
          {'id': '30280', 'baseUrl': 'https://a/'},
        ],
      },
    };
    final r = BiliPlayUrlResult.fromJson(json);
    expect(r.quality, 80);
    expect(r.timelength, 1423000);
    expect(r.acceptQuality, [80, 64]);
    expect(r.videos.single.width, 1920);
  });

  test('dolby/flac 音频合并进 audios', () {
    final json = {
      'quality': 80,
      'dash': {
        'flac': {
          'audio': {'id': 30251, 'baseUrl': 'https://flac/'},
        },
        'dolby': {
          'audio': [
            {'id': 30250, 'baseUrl': 'https://dolby/'},
          ],
        },
        'audio': [
          {'id': 30280, 'baseUrl': 'https://aac/'},
        ],
      },
    };
    final r = BiliPlayUrlResult.fromJson(json);
    expect(r.audios.map((a) => a.id), [30251, 30250, 30280]);
  });

  test('BiliUgcVideo 取首分 P cid 与标题', () {
    final json = {
      'aid': 123,
      'bvid': 'BV1xx411c7mD',
      'title': '标题',
      'pages': [
        {'cid': 456, 'duration': 90},
        {'cid': 789},
      ],
    };
    final v = BiliUgcVideo.fromJson(json);
    expect(v.aid, 123);
    expect(v.bvid, 'BV1xx411c7mD');
    expect(v.cid, 456);
    expect(v.title, '标题');
    expect(v.durationMs, 90000);
  });

  test('BiliUgcVideo 解析全部分 P（多 P 补全）', () {
    final json = {
      'aid': 123,
      'bvid': 'BV1xx411c7mD',
      'title': '标题',
      'pages': [
        {'cid': 456, 'page': 1, 'part': 'P1 片头', 'duration': 90},
        {'cid': 789, 'page': 2, 'part': 'P2 正片', 'duration': 300},
      ],
    };
    final v = BiliUgcVideo.fromJson(json);
    expect(v.pages.length, 2);
    expect(v.pages[0].cid, 456);
    expect(v.pages[0].part, 'P1 片头');
    expect(v.pages[1].cid, 789);
    expect(v.pages[1].durationMs, 300000);
    // 向后兼容：cid 仍取首分 P
    expect(v.cid, 456);
  });
}
