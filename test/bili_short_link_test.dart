import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/services/bilibili/bili_download_service.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';
import 'package:moumou/utils/bili_short_link.dart';

/// b23.tv 分享短链展开测试（工作.md 第 8 点：短链不含 BV/av/ss/ep 令牌，
/// 须跟随 302 拿真实 URL 才能被 parseBiliBangumiUrl 识别）。
void main() {
  group('extractBiliShortLink（从任意文本提取）', () {
    test('App 分享完整文本（带【标题】中文前缀）', () {
      final text =
          '【【4K超清】时光流逝 饭菜依旧美味 1-12话（完结撒花，推荐观看）-哔哩哔哩】 '
          'https://b23.tv/NkRjTgm';
      expect(extractBiliShortLink(text), 'https://b23.tv/NkRjTgm');
    });

    test('裸短链（无协议）自动补 https', () {
      expect(extractBiliShortLink('b23.tv/NkRjTgm'), 'https://b23.tv/NkRjTgm');
    });

    test('host 大小写不敏感（原样返回匹配文本）', () {
      expect(extractBiliShortLink('看这个 HTTPS://B23.TV/AbC123'),
          'HTTPS://B23.TV/AbC123');
    });

    test('无短链的文本返回 null（纯 BV 号 / 纯中文）', () {
      expect(extractBiliShortLink('BV1xx411c7mD'), isNull);
      expect(extractBiliShortLink('随便一段文字'), isNull);
    });
  });

  test('无短链的输入直接返回 null（不发请求）', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      return http.Response('', 200);
    });
    expect(await expandBiliShortLink('BV1xx411c7mD', client: client), isNull);
    expect(await expandBiliShortLink('随便一段文字', client: client), isNull);
    expect(requests, 0);
  });

  test('App 分享完整文本（带【标题】前缀）也能展开', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      expect(req.url.host, 'b23.tv');
      return http.Response('', 302, headers: {
        'location': 'https://www.bilibili.com/video/BV1GJ411x7h7?p=1',
      });
    });
    final expanded = await expandBiliShortLink(
      '【【4K超清】时光流逝 饭菜依旧美味 1-12话（完结撒花，推荐观看）-哔哩哔哩】 '
      'https://b23.tv/NkRjTgm',
      client: client,
      isTarget: (url) => parseBiliBangumiUrl(url) != null,
    );
    expect(requests, 1);
    expect(expanded, 'https://www.bilibili.com/video/BV1GJ411x7h7?p=1');
  });

  test('裸短链（无协议）也能展开', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'b23.tv');
      return http.Response('', 302, headers: {
        'location': 'https://www.bilibili.com/video/BV1GJ411x7h7',
      });
    });
    final expanded = await expandBiliShortLink(
      'b23.tv/NkRjTgm',
      client: client,
      isTarget: (url) => parseBiliBangumiUrl(url) != null,
    );
    expect(expanded, 'https://www.bilibili.com/video/BV1GJ411x7h7');
  });

  test('302 跳转到 BV 链接：命中令牌即停（只发 1 个请求，不下载页面）', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      expect(req.url.host, 'b23.tv');
      expect(req.followRedirects, isFalse);
      expect(req.headers['User-Agent'], isNotEmpty);
      return http.Response('', 302, headers: {
        'location': 'https://www.bilibili.com/video/BV1GJ411x7h7?p=1',
      });
    });
    final expanded = await expandBiliShortLink(
      'https://b23.tv/NkRjTgm',
      client: client,
      isTarget: (url) => parseBiliBangumiUrl(url) != null,
    );
    expect(requests, 1);
    expect(expanded, 'https://www.bilibili.com/video/BV1GJ411x7h7?p=1');
  });

  test('多跳重定向逐跳跟随（b23.tv → 中转 → 番剧 ss 链接）', () async {
    final hops = <String>[];
    final client = MockClient((req) async {
      hops.add(req.url.host);
      if (req.url.host == 'b23.tv') {
        return http.Response('', 302,
            headers: {'location': 'https://t.bilibili.com/redirect'});
      }
      if (req.url.host == 't.bilibili.com') {
        return http.Response('', 302,
            headers: {'location': 'https://www.bilibili.com/bangumi/play/ss12345'});
      }
      return http.Response('', 200);
    });
    final expanded = await expandBiliShortLink(
      'https://b23.tv/abc',
      client: client,
      isTarget: (url) => parseBiliBangumiUrl(url) != null,
    );
    expect(expanded, 'https://www.bilibili.com/bangumi/play/ss12345');
    expect(hops, ['b23.tv', 't.bilibili.com']); // 命中 ss 后不再请求
  });

  test('非重定向响应：返回当前 URL（不读 body）', () async {
    final client = MockClient((req) async => http.Response('<html>...</html>', 200));
    final expanded = await expandBiliShortLink('https://b23.tv/xyz', client: client);
    expect(expanded, 'https://b23.tv/xyz');
  });

  test('请求抛异常 → 返回 null', () async {
    final client = MockClient((req) async => throw Exception('network down'));
    expect(await expandBiliShortLink('https://b23.tv/xyz', client: client), isNull);
  });

  group('BiliDownloadService.resolveRef', () {
    test('App 分享完整文本（【标题】+ 短链）→ 展开后解析出 UGC 引用', () async {
      final client = MockClient((req) async => http.Response('', 302, headers: {
            'location':
                'https://www.bilibili.com/video/BV1GJ411x7h7?share_source=copy_web',
          }));
      final service = BiliDownloadService(linkClient: client);
      final ref = await service.resolveRef(
        '【【4K超清】时光流逝 饭菜依旧美味 1-12话（完结撒花，推荐观看）-哔哩哔哩】 '
        'https://b23.tv/NkRjTgm',
      );
      expect(ref, isNotNull);
      expect(ref!.isUgc, isTrue);
      expect(ref.bvid, 'BV1GJ411x7h7');
    });

    test('b23.tv 短链 → 展开后解析出 UGC 引用', () async {
      final client = MockClient((req) async => http.Response('', 302, headers: {
            'location':
                'https://www.bilibili.com/video/BV1GJ411x7h7?share_source=copy_web',
          }));
      final service = BiliDownloadService(linkClient: client);
      final ref = await service.resolveRef('https://b23.tv/NkRjTgm');
      expect(ref, isNotNull);
      expect(ref!.isUgc, isTrue);
      expect(ref.bvid, 'BV1GJ411x7h7');
    });

    test('短链跳到番剧 → 解析出 ss 引用', () async {
      final client = MockClient((req) async => http.Response('', 302, headers: {
            'location': 'https://www.bilibili.com/bangumi/play/ss42410',
          }));
      final service = BiliDownloadService(linkClient: client);
      final ref = await service.resolveRef('https://b23.tv/xyz');
      expect(ref, isNotNull);
      expect(ref!.hasSeason, isTrue);
      expect(ref.seasonId, 42410);
    });

    test('直接含 BV 的输入不触发网络请求', () async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        return http.Response('', 200);
      });
      final service = BiliDownloadService(linkClient: client);
      final ref = await service.resolveRef('https://www.bilibili.com/video/BV1GJ411x7h7');
      expect(ref, isNotNull);
      expect(ref!.bvid, 'BV1GJ411x7h7');
      expect(requests, 0);
    });

    test('展开后仍无法识别 → null', () async {
      final client = MockClient(
          (req) async => http.Response('', 302, headers: {'location': 'https://example.com/abc'}));
      final service = BiliDownloadService(linkClient: client);
      expect(await service.resolveRef('https://b23.tv/xyz'), isNull);
      expect(await service.resolveRef('hello world'), isNull);
    });
  });
}
