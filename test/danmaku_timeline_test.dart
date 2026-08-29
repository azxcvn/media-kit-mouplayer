import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/danmaku_timeline.dart';

/// 弹幕时间轴纯函数测试：同秒多条弹幕的 1 秒内错峰延迟。
void main() {
  group('staggerDelayMilliseconds（同秒错峰）', () {
    test('总数 <= 0 → 0', () {
      expect(staggerDelayMilliseconds(index: 0, total: 0), 0);
      expect(staggerDelayMilliseconds(index: 3, total: -1), 0);
    });

    test('单条 → 延迟 0', () {
      expect(staggerDelayMilliseconds(index: 0, total: 1), 0);
    });

    test('同秒 4 条 → 0 / 250 / 500 / 750（1 秒内均分）', () {
      expect(staggerDelayMilliseconds(index: 0, total: 4), 0);
      expect(staggerDelayMilliseconds(index: 1, total: 4), 250);
      expect(staggerDelayMilliseconds(index: 2, total: 4), 500);
      expect(staggerDelayMilliseconds(index: 3, total: 4), 750);
    });

    test('延迟始终 < 1000ms（错峰不跨出 1 秒窗口）', () {
      for (final total in [2, 3, 5, 10, 30]) {
        for (var i = 0; i < total; i++) {
          final delay = staggerDelayMilliseconds(index: i, total: total);
          expect(delay, lessThan(1000));
          expect(delay, greaterThanOrEqualTo(0));
        }
      }
    });
  });
}
