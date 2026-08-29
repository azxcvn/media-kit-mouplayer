import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/utils/danmaku_xml.dart';

/// B站 XML 弹幕解析测试：基础字段 / 实体反转义 / 容错跳过 / 排序。
void main() {
  group('parseDanmakuXml（基础解析）', () {
    test('标准条目：时间/模式/颜色/文本', () {
      final xml = '<?xml version="1.0" encoding="UTF-8"?>'
          '<i>'
          '<chatserver>chat.bilibili.com</chatserver>'
          '<d p="1.500,1,25,16777215,1650000000,0,abc123,3919">前方高能</d>'
          '<d p="42.250,4,25,16711680,1650000001,0,def456,3920">底部弹幕</d>'
          '<d p="60.000,5,25,65280,1650000002,0,ghi789,3921">顶部弹幕</d>'
          '</i>';
      final entries = parseDanmakuXml(xml);
      expect(entries.length, 3);
      expect(entries[0],
          const DanmakuEntry(time: 1.5, mode: 1, color: 16777215, text: '前方高能'));
      expect(entries[1],
          const DanmakuEntry(time: 42.25, mode: 4, color: 16711680, text: '底部弹幕'));
      expect(entries[2],
          const DanmakuEntry(time: 60.0, mode: 5, color: 65280, text: '顶部弹幕'));
    });

    test('秒桶取整：time.floor()', () {
      final entries = parseDanmakuXml(
          '<d p="9.999,1,25,16777215,0,0,0,0">a</d>'
          '<d p="10.000,1,25,16777215,0,0,0,0">b</d>');
      expect(entries[0].timeSeconds, 9);
      expect(entries[1].timeSeconds, 10);
    });

    test('按时间升序排序（乱序输入）', () {
      final entries = parseDanmakuXml(
          '<d p="30.0,1,25,16777215,0,0,0,0">c</d>'
          '<d p="1.0,1,25,16777215,0,0,0,0">a</d>'
          '<d p="15.5,1,25,16777215,0,0,0,0">b</d>');
      expect(entries.map((e) => e.text).toList(), ['a', 'b', 'c']);
    });
  });

  group('parseDanmakuXml（实体反转义）', () {
    test('命名实体 amp/lt/gt/quot/apos', () {
      final entries = parseDanmakuXml(
          '<d p="1.0,1,25,16777215,0,0,0,0">'
          '&amp;&lt;&gt;&quot;&apos;'
          '</d>');
      expect(entries.single.text, '&<>"\'');
    });

    test('数字实体（十进制 / 十六进制）', () {
      final entries = parseDanmakuXml(
          '<d p="1.0,1,25,16777215,0,0,0,0">&#65;&#x42;</d>');
      expect(entries.single.text, 'AB');
    });

    test('非实体裸 & 原样保留', () {
      final entries = parseDanmakuXml(
          '<d p="1.0,1,25,16777215,0,0,0,0">A &amp; B & C</d>');
      expect(entries.single.text, 'A & B & C');
    });
  });

  group('parseDanmakuXml（容错）', () {
    test('坏条目逐条跳过（p 缺失 / 字段不足 / 时间非法 / 文本空）', () {
      final xml = '<i>'
          '<d p="1.0,1,25,16777215,0,0,0,0">ok1</d>'
          '<d>无 p 属性</d>'
          '<d p="1.0,1">字段不足</d>'
          '<d p="abc,1,25,16777215,0,0,0,0">时间非法</d>'
          '<d p="-5.0,1,25,16777215,0,0,0,0">负时间</d>'
          '<d p="2.0,1,25,16777215,0,0,0,0">   </d>'
          '<d p="3.0,1,25,16777215,0,0,0,0">ok2</d>'
          '</i>';
      final entries = parseDanmakuXml(xml);
      expect(entries.map((e) => e.text).toList(), ['ok1', 'ok2']);
    });

    test('mode/颜色解析失败回退默认（1 / 白色）', () {
      final entries = parseDanmakuXml(
          '<d p="1.0,xx,25,notacolor,0,0,0,0">fallback</d>');
      expect(entries.single.mode, 1);
      expect(entries.single.color, 0xFFFFFF);
    });

    test('颜色掩码到 24 位 RGB（负数 / 超界值不炸）', () {
      final entries = parseDanmakuXml(
          '<d p="1.0,1,25,-1,0,0,0,0">neg</d>');
      expect(entries.single.color, 0xFFFFFF);
    });

    test('非弹幕 XML / 空内容 → 空列表', () {
      expect(parseDanmakuXml('<html><body>not danmaku</body></html>'), isEmpty);
      expect(parseDanmakuXml(''), isEmpty);
    });

    test('多行文本（dotAll）与 CRLF 换行可解析', () {
      final xml = '<i>\r\n<d p="1.0,1,25,16777215,0,0,0,0">第一行</d>\r\n'
          '<d p="2.0,1,25,16777215,0,0,0,0">第二行</d>\r\n</i>';
      expect(parseDanmakuXml(xml).length, 2);
    });
  });

  group('unescapeXml（单独验证）', () {
    test('无实体直通（不新建字符串路径）', () {
      expect(unescapeXml('plain text'), 'plain text');
    });

    test('非法数字实体原样保留', () {
      expect(unescapeXml('&#99999999999;'), '&#99999999999;');
      expect(unescapeXml('&#xZZ;'), '&#xZZ;');
    });
  });
}
