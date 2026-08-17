import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/natural_compare.dart';

/// 自然序比较工具测试（名称排序的纯函数）
void main() {
  group('naturalCompare', () {
    test('纯数字：按数值排序（112 不再排在 12 前）', () {
      final list = ['112', '12', '2', '9', '10', '1'];
      list.sort(naturalCompare);
      expect(list, ['1', '2', '9', '10', '12', '112']);
    });

    test('数字夹在文本中：第2话 < 第12话 < 第112话', () {
      final list = ['第112话', '第12话', '第2话', '第1话'];
      list.sort(naturalCompare);
      expect(list, ['第1话', '第2话', '第12话', '第112话']);
    });

    test('文件名：2.mp4 < 12.mp4 < 112.mp4', () {
      final list = ['12.mp4', '2.mp4', '112.mp4', '3.mp4'];
      list.sort(naturalCompare);
      expect(list, ['2.mp4', '3.mp4', '12.mp4', '112.mp4']);
    });

    test('字母段大小写不敏感', () {
      final list = ['b', 'A', 'ab', 'C'];
      list.sort(naturalCompare);
      expect(list, ['A', 'ab', 'b', 'C']);
    });

    test('前缀更短优先', () {
      final list = ['abc', 'ab', 'a'];
      list.sort(naturalCompare);
      expect(list, ['a', 'ab', 'abc']);
    });

    test('混合字母数字：a1 < a2 < a10', () {
      final list = ['a10', 'a1', 'a2'];
      list.sort(naturalCompare);
      expect(list, ['a1', 'a2', 'a10']);
    });

    test('相等字符串返回 0', () {
      expect(naturalCompare('第12话', '第12话'), 0);
    });

    test('空串与非空串', () {
      expect(naturalCompare('', ''), 0);
      expect(naturalCompare('', 'a'), lessThan(0));
      expect(naturalCompare('a', ''), greaterThan(0));
    });
  });
}
