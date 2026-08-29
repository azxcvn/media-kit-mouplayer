import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/utils/danmaku_dedup.dart';

/// 弹幕去重纯函数测试：归一化判同、时间窗合并、无序输入、边界。
void main() {
  DanmakuEntry e(double time, String text, {int mode = 1, int color = 0xFFFFFF}) =>
      DanmakuEntry(time: time, mode: mode, color: color, text: text);

  group('normalizeDanmakuText', () {
    test('大小写/全角/空白归一化', () {
      expect(normalizeDanmakuText('前方高能'), normalizeDanmakuText('前方高能'));
      expect(normalizeDanmakuText('LOL'), normalizeDanmakuText('lol'));
      expect(normalizeDanmakuText('６６６'), normalizeDanmakuText('666')); // 全角数字
      expect(normalizeDanmakuText('６６６'.replaceAll('６', '６')), isNotEmpty);
      expect(normalizeDanmakuText('a b　c'), 'abc'); // 半角+全角空格去除
    });

    test('连续相同字符收敛为 3 个', () {
      expect(normalizeDanmakuText('666666'), normalizeDanmakuText('666'));
      expect(normalizeDanmakuText('哈哈哈哈哈哈'), normalizeDanmakuText('哈哈哈'));
    });

    test('标点去除', () {
      expect(normalizeDanmakuText('太棒了!!!'), normalizeDanmakuText('太棒了'));
      expect(normalizeDanmakuText('666~'), normalizeDanmakuText('666'));
    });

    test('纯标点归一化为空', () {
      expect(normalizeDanmakuText('！！！'), isEmpty);
    });
  });

  group('dedupeDanmakuEntries', () {
    test('时间窗内相同内容只保留首条', () {
      final result = dedupeDanmakuEntries([
        e(10, '前方高能'),
        e(12, '前方高能'),
        e(14, '前方高能'), // 14 - 10 = 4 ≤ 5 → 合并
        e(16, '前方高能'), // 16 - 10 = 6 > 5 → 保留（相对上次保留点 10）
      ]);
      expect(result.length, 2);
      expect(result[0].time, 10);
      expect(result[1].time, 16);
    });

    test('窗口按上次保留点推进（链式去重）', () {
      final result = dedupeDanmakuEntries([
        e(0, 'aaa'),
        e(4, 'aaa'),
        e(8, 'aaa'),
      ]);
      // 0 保留 → 4 在窗内丢 → 8 相对 0 = 8 > 5 保留
      expect(result.map((x) => x.time).toList(), [0, 8]);
    });

    test('不同内容不去重', () {
      final result = dedupeDanmakuEntries([
        e(10, '前方高能'),
        e(11, '保护我方太太'),
        e(12, '弹幕护体'),
      ]);
      expect(result.length, 3);
    });

    test('归一化后相同视为重复（大小写/连续字收敛）', () {
      final result = dedupeDanmakuEntries([
        e(10, 'LOL'),
        e(11, 'lol!!'),
        e(12, '6666666'),
        e(13, '666'),
      ]);
      expect(result.length, 2);
      expect(result[0].text, 'LOL');
      expect(result[1].text, '6666666');
    });

    test('保留首条的时间/颜色/模式（原文原样）', () {
      final result = dedupeDanmakuEntries([
        e(5, '测试', mode: 5, color: 0xFF0000),
        e(6, '测试'),
      ]);
      expect(result.single.time, 5);
      expect(result.single.mode, 5);
      expect(result.single.color, 0xFF0000);
      expect(result.single.text, '测试');
    });

    test('无序输入也正确（按时间排序后处理）', () {
      final result = dedupeDanmakuEntries([
        e(12, '前排'),
        e(10, '前排'),
        e(11, '前排'),
      ]);
      expect(result.single.time, 10);
    });

    test('单条与空列表原样返回', () {
      expect(dedupeDanmakuEntries([]), isEmpty);
      expect(dedupeDanmakuEntries([e(1, 'x')]).length, 1);
    });

    test('自定义时间窗', () {
      final result = dedupeDanmakuEntries(
        [e(0, 'dup'), e(9, 'dup')],
        windowSeconds: 10,
      );
      expect(result.length, 1);
    });

    test('时间窗默认 5 秒', () {
      expect(kDanmakuDedupWindowSeconds, 5);
    });
  });
}
