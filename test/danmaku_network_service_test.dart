import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/services/dandan_play_api.dart';
import 'package:moumou/services/danmaku_network_service.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:moumou/utils/danmaku_xml.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕网络服务测试：文件名清洗、搜索合并、下载落盘（持久化）。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DanmakuServerSettings.instance.resetForTest();
    DanmakuNetworkService.debugDirectoryOverride = null;
  });

  group('networkDanmakuFileName', () {
    test('保留中文/字母/数字/下划线，追加 .xml', () {
      expect(
        networkDanmakuFileName('紫罗兰永恒花园', '第01话', 42),
        '紫罗兰永恒花园_第01话_42.xml',
      );
    });

    test('非法字符（空格/中括号/短横等）替换为下划线', () {
      final name =
          networkDanmakuFileName('[B-Global] Violet Evergarden', 'EP 01 [1080p]', 7);
      final base = name.substring(0, name.length - 4); // 去掉 .xml
      expect(RegExp(r'[^a-zA-Z0-9_\u4e00-\u9fa5]').hasMatch(base), isFalse);
      expect(base.contains('Violet'), isTrue);
      expect(base.contains('1080p'), isTrue);
      expect(base.contains('_7'), isTrue);
    });
  });

  group('search 合并（MockClient）', () {
    test('默认+自建服务器结果合并，animeId 去重，记录来源服务器', () async {
      final api = DandanPlayApi(
        client: MockClient((request) async {
          if (request.url.host == 'api.dandanplay.net') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'animes': [
                  _animeJson(1, '番剧A', [
                    _epJson(11, '第01话'),
                  ]),
                ],
              })),
              200,
            );
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'animes': [
                _animeJson(1, '番剧A', [
                  _epJson(11, '第01话'),
                ]),
                _animeJson(2, '番剧B', [
                  _epJson(22, '第02话'),
                ]),
              ],
            })),
            200,
          );
        }),
      );
      final service = DanmakuNetworkService(api: api);
      await DanmakuServerSettings.instance.addServer('我的服务器', 'https://self.example.com');

      final result = await service.search('关键词');
      expect(result.items.length, 2);
      expect(result.items[0].anime.animeId, 1);
      expect(result.items[0].serverUrl, isNull); // 默认服务器先到先得
      expect(result.items[0].serverName, DanmakuServerSettings.instance.servers.first.name);
      expect(result.items[1].anime.animeId, 2);
      expect(result.items[1].serverUrl, 'https://self.example.com');
      expect(result.items[1].serverName, '我的服务器');
      expect(result.errors, isEmpty);
    });

    test('单服务器失败记录错误，不阻断其余服务器结果', () async {
      final api = DandanPlayApi(
        client: MockClient((request) async {
          if (request.url.host == 'api.dandanplay.net') {
            return http.Response('server error', 500);
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'animes': [
                _animeJson(2, '番剧B', [
                  _epJson(22, '第02话'),
                ]),
              ],
            })),
            200,
          );
        }),
      );
      final service = DanmakuNetworkService(api: api);
      await DanmakuServerSettings.instance.addServer('我的服务器', 'https://self.example.com');

      final result = await service.search('关键词');
      expect(result.items.length, 1);
      expect(result.items.single.anime.animeId, 2);
      expect(result.errors.length, 1);
      expect(result.errors.single, contains('弹弹Play'));
    });
  });

  group('downloadEpisode 落盘（持久化）', () {
    test('拉取 → 条目 + B站 XML 落盘 → 可回读解析', () async {
      final tmp = await Directory.systemTemp.createTemp('danmaku_net');
      DanmakuNetworkService.debugDirectoryOverride =
          () async => Directory(p.join(tmp.path, 'network'));

      final api = DandanPlayApi(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'count': 2,
              'comments': [
                {'cid': 1, 'p': '1.500,1,16777215,u', 'm': '前方高能'},
                {'cid': 2, 'p': '60.000,5,65280,u', 'm': '顶部弹幕'},
              ],
            })),
            200,
          );
        }),
      );
      final service = DanmakuNetworkService(api: api);
      final download = await service.downloadEpisode(
        episodeId: 42,
        animeTitle: '紫罗兰永恒花园',
        episodeTitle: '第01话',
      );

      expect(download.entries.map((e) => e.text).toList(), ['前方高能', '顶部弹幕']);
      expect(download.filePathOrNull, isNotNull);
      final content = await File(download.filePathOrNull!).readAsString();
      expect(
        parseDanmakuXml(content).map((e) => e.text).toList(),
        ['前方高能', '顶部弹幕'],
      );

      await tmp.delete(recursive: true);
    });

    test('目录不可用（无 path_provider）仍返回条目，filePath 为 null', () async {
      // 不注入目录覆盖 → getApplicationSupportDirectory 在测试环境抛
      // MissingPluginException，落盘失败但不影响本次播放。
      final api = DandanPlayApi(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'count': 1,
              'comments': [
                {'cid': 1, 'p': '1.0,1,255,u', 'm': '单条'},
              ],
            })),
            200,
          );
        }),
      );
      final service = DanmakuNetworkService(api: api);
      final download = await service.downloadEpisode(
        episodeId: 1,
        animeTitle: '番剧',
        episodeTitle: '第01话',
      );
      expect(download.entries.single.text, '单条');
      expect(download.filePathOrNull, isNull);
    });

    test('空弹幕不落盘', () async {
      final tmp = await Directory.systemTemp.createTemp('danmaku_net2');
      DanmakuNetworkService.debugDirectoryOverride =
          () async => Directory(p.join(tmp.path, 'network'));
      final api = DandanPlayApi(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({'count': 0, 'comments': []})),
            200,
          );
        }),
      );
      final service = DanmakuNetworkService(api: api);
      final download = await service.downloadEpisode(
        episodeId: 1,
        animeTitle: '番剧',
        episodeTitle: '第01话',
      );
      expect(download.entries, isEmpty);
      expect(download.filePathOrNull, isNull);

      await tmp.delete(recursive: true);
    });
  });
}

Map<String, dynamic> _animeJson(int id, String title, List<Map<String, dynamic>> episodes) =>
    {
      'animeId': id,
      'animeTitle': title,
      'type': 'tv',
      'typeDescription': 'TV',
      'episodes': episodes,
    };

Map<String, dynamic> _epJson(int id, String title) =>
    {'episodeId': id, 'episodeTitle': title};
