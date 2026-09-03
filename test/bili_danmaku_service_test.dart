import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/services/bilibili/bili_danmaku_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/danmaku_xml.dart';

import 'pb_test_helper.dart';

void main() {
  test('danmakuEntriesToBiliXml 生成标准 XML 且可回读', () {
    final entries = [
      DanmakuEntry(time: 1.5, mode: 1, color: 0xFFFFFF, text: '你好<世界>&'),
    ];
    final xml = danmakuEntriesToBiliXml(entries);
    expect(xml, contains('<d p="1.5,1,25,16777215,0,0,0,0">'));
    expect(xml, contains('你好&lt;世界&gt;&amp;'));
    final parsed = parseDanmakuXml(xml);
    expect(parsed.length, 1);
    expect(parsed.first.text, '你好<世界>&');
    expect(parsed.first.time, 1.5);
  });

  test('fetchDanmaku 走 protobuf 分段并解码、去重、按时间排序', () async {
    final seg1 = encodeSegMobileReply([
      encodeDanmakuElem(id: 1, progressMs: 1000, mode: 1, content: '第一条'),
      encodeDanmakuElem(
          id: 2, progressMs: 2000, mode: 5, color: 0xFF0000, content: '第二条'),
    ]);
    final seg2 = encodeSegMobileReply([
      encodeDanmakuElem(
          id: 3, progressMs: 500, mode: 4, color: 0x00FF00, content: '第三条'),
    ]);
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p == '/x/v2/dm/web/view') {
        return http.Response.bytes(encodeWebViewReply(2), 200);
      }
      if (p == '/x/v2/dm/web/seg.so') {
        final idx = int.parse(req.url.queryParameters['segment_index']!);
        return http.Response.bytes(idx == 1 ? seg1 : seg2, 200);
      }
      return http.Response('not found', 404);
    });
    final service = BiliDanmakuService(http: BiliHttp(client: client));
    final entries = await service.fetchDanmaku(cid: 999, aid: 1);
    expect(entries.map((e) => e.text).toList(), ['第三条', '第一条', '第二条']);
    expect(entries.first.time, 0.5);
    expect(entries[1].time, 1.0);
    expect(entries[1].mode, 1);
    expect(entries[2].mode, 5);
    expect(entries[2].color, 0xFF0000);
  });

  test('跨分段按 id 去重', () async {
    final seg1 = encodeSegMobileReply([
      encodeDanmakuElem(id: 1, progressMs: 1000, content: '重复'),
    ]);
    final seg2 = encodeSegMobileReply([
      encodeDanmakuElem(id: 1, progressMs: 1000, content: '重复'),
      encodeDanmakuElem(id: 2, progressMs: 2000, content: '唯一'),
    ]);
    final client = MockClient((req) async {
      if (req.url.path == '/x/v2/dm/web/view') {
        return http.Response.bytes(encodeWebViewReply(2), 200);
      }
      final idx = int.parse(req.url.queryParameters['segment_index']!);
      return http.Response.bytes(idx == 1 ? seg1 : seg2, 200);
    });
    final service = BiliDanmakuService(http: BiliHttp(client: client));
    final entries = await service.fetchDanmaku(cid: 1);
    expect(entries.length, 2);
  });

  test('state==1 弹幕关闭且降级失败时返回空（不抛）', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/x/v2/dm/web/view') {
        return http.Response.bytes(encodeWebViewReply(1), 200);
      }
      if (req.url.host == 'comment.bilibili.com') {
        return http.Response('err', 500);
      }
      return http.Response.bytes(encodeSegMobileReply(const [], state: 1), 200);
    });
    final service = BiliDanmakuService(http: BiliHttp(client: client));
    final entries = await service.fetchDanmaku(cid: 1);
    expect(entries, isEmpty);
  });

  test('protobuf 失败降级旧 XML（raw deflate）', () async {
    final xml = '<?xml version="1.0" encoding="UTF-8"?><i>'
        '<d p="1.0,1,25,16777215,0,0,0,0">降级弹幕</d></i>';
    final deflated = ZLibEncoder(raw: true).convert(utf8.encode(xml));
    final client = MockClient((req) async {
      if (req.url.host == 'comment.bilibili.com') {
        return http.Response.bytes(deflated, 200);
      }
      return http.Response('err', 500); // protobuf 路径失败
    });
    final service = BiliDanmakuService(http: BiliHttp(client: client));
    final entries = await service.fetchDanmaku(cid: 1);
    expect(entries.single.text, '降级弹幕');
  });

  test('缓存落盘 + 回读', () async {
    final tmp = Directory.systemTemp.createTempSync('bili_dm_test');
    BiliDanmakuService.debugDirectoryOverride = () async => tmp;
    try {
      final service = BiliDanmakuService();
      final entries = [
        DanmakuEntry(time: 2.0, mode: 1, color: 0xFFFFFF, text: '缓存弹幕'),
      ];
      final path = await service.cacheDanmaku(12345, entries);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      final loaded = await service.loadCachedDanmaku(12345);
      expect(loaded!.single.text, '缓存弹幕');
    } finally {
      BiliDanmakuService.debugDirectoryOverride = null;
      tmp.deleteSync(recursive: true);
    }
  });
}
