import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/utils/dandan_comment.dart';
import 'package:moumou/utils/danmaku_xml.dart';

/// 弹弹Play 评论 → 弹幕条目 / B站 XML 转换纯函数测试。
void main() {
  test('标准评论：time,mode,color 转 DanmakuEntry', () {
    const comments = [
      DandanComment(cid: 1, p: '1.500,1,16777215,user1', m: '前方高能'),
      DandanComment(cid: 2, p: '42.250,4,16711680,user2', m: '底部弹幕'),
      DandanComment(cid: 3, p: '60.000,5,65280,user3', m: '顶部弹幕'),
    ];
    final entries = dandanCommentsToEntries(comments);
    expect(entries.length, 3);
    expect(entries[0],
        const DanmakuEntry(time: 1.5, mode: 1, color: 16777215, text: '前方高能'));
    expect(entries[1],
        const DanmakuEntry(time: 42.25, mode: 4, color: 16711680, text: '底部弹幕'));
    expect(entries[2],
        const DanmakuEntry(time: 60.0, mode: 5, color: 65280, text: '顶部弹幕'));
  });

  test('p 字段只有 3 段（无 userId）也能解析', () {
    const comments = [DandanComment(cid: 1, p: '5.0,1,255', m: 'ok')];
    final entries = dandanCommentsToEntries(comments);
    expect(entries.single.text, 'ok');
    expect(entries.single.time, 5.0);
    expect(entries.single.color, 255);
  });

  test('文本去除首尾空白', () {
    const comments = [DandanComment(cid: 1, p: '1,1,16777215', m: '  内容  ')];
    expect(dandanCommentsToEntries(comments).single.text, '内容');
  });

  test('损坏条目跳过：p 字段不足 / 时间非法 / 文本空', () {
    const comments = [
      DandanComment(cid: 1, p: '1.0,1,255', m: 'ok1'),
      DandanComment(cid: 2, p: '1.0,1', m: '字段不足'),
      DandanComment(cid: 3, p: 'abc,1,255', m: '时间非法'),
      DandanComment(cid: 4, p: '-3.0,1,255', m: '负时间'),
      DandanComment(cid: 5, p: '2.0,1,255', m: '   '),
      DandanComment(cid: 6, p: '3.0,1,255', m: 'ok2'),
    ];
    final entries = dandanCommentsToEntries(comments);
    expect(entries.map((e) => e.text).toList(), ['ok1', 'ok2']);
  });

  test('mode/颜色解析失败回退默认（1 / 白色）', () {
    const comments = [DandanComment(cid: 1, p: '1.0,xx,notacolor', m: 'fallback')];
    final e = dandanCommentsToEntries(comments).single;
    expect(e.mode, 1);
    expect(e.color, 0xFFFFFF);
  });

  test('颜色掩码到 24 位 RGB', () {
    const comments = [DandanComment(cid: 1, p: '1.0,1,-1', m: 'neg')];
    expect(dandanCommentsToEntries(comments).single.color, 0xFFFFFF);
  });

  test('结果按时间升序排序（乱序输入）', () {
    const comments = [
      DandanComment(cid: 1, p: '30.0,1,255', m: 'c'),
      DandanComment(cid: 2, p: '1.0,1,255', m: 'a'),
      DandanComment(cid: 3, p: '15.5,1,255', m: 'b'),
    ];
    expect(
      dandanCommentsToEntries(comments).map((e) => e.text).toList(),
      ['a', 'b', 'c'],
    );
  });

  test('空列表 → 空结果', () {
    expect(dandanCommentsToEntries(const []), isEmpty);
  });

  group('dandanCommentsToXml（落盘 B站 XML）', () {
    test('生成 XML 可被 parseDanmakuXml 还原为相同条目', () {
      const comments = [
        DandanComment(cid: 1, p: '1.500,1,16777215,u', m: '前方高能'),
        DandanComment(cid: 2, p: '42.250,4,16711680,u', m: '底部弹幕'),
      ];
      final xml = dandanCommentsToXml(comments);
      expect(xml.contains('<source>DanDanPlay</source>'), isTrue);
      expect(parseDanmakuXml(xml), dandanCommentsToEntries(comments));
    });

    test('文本特殊字符（& < > " \'）转义后往返一致', () {
      const comments = [
        DandanComment(cid: 1, p: '1.0,1,255,u', m: 'A&B<C>"D\'E'),
      ];
      final xml = dandanCommentsToXml(comments);
      expect(parseDanmakuXml(xml).single.text, 'A&B<C>"D\'E');
    });

    test('损坏条目跳过（与条目转换规则一致）', () {
      const comments = [
        DandanComment(cid: 1, p: '1.0,1,255,u', m: 'ok'),
        DandanComment(cid: 2, p: 'bad', m: 'x'),
        DandanComment(cid: 3, p: '-2.0,1,255,u', m: '负时间'),
      ];
      final xml = dandanCommentsToXml(comments);
      expect(RegExp('<d ').allMatches(xml).length, 1);
    });

    test('空列表 → 仅头尾标签', () {
      final xml = dandanCommentsToXml(const []);
      expect(xml.contains('<source>DanDanPlay</source>'), isTrue);
      expect(parseDanmakuXml(xml), isEmpty);
    });
  });
}
