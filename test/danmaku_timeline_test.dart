import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/danmaku_timeline.dart';

/// 弹幕时间轴纯函数测试：同秒多条弹幕的 1 秒内错峰延迟 + 时间轴偏移。
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

  group('sourceDanmakuPosition（时间轴偏移）', () {
    test('零偏移：源时间 = 播放时间', () {
      const p = Duration(seconds: 100);
      expect(sourceDanmakuPosition(p, 0), p);
    });

    test('正偏移（延后）：源时间提前 offset 秒', () {
      const p = Duration(seconds: 100);
      expect(sourceDanmakuPosition(p, 5), const Duration(seconds: 95));
    });

    test('负偏移（提前）：源时间延后 |offset| 秒', () {
      const p = Duration(seconds: 100);
      expect(sourceDanmakuPosition(p, -5), const Duration(seconds: 105));
    });

    test('偏移后早于片头：返回负 Duration（调度器视为空桶）', () {
      const p = Duration(seconds: 3);
      expect(sourceDanmakuPosition(p, 10), const Duration(seconds: -7));
    });
  });

  group('formatDanmakuTimeOffset（偏移展示）', () {
    test('0 → 无偏移', () {
      expect(formatDanmakuTimeOffset(0), '无偏移');
    });

    test('正 → 延后 MM:SS', () {
      expect(formatDanmakuTimeOffset(45), '延后 00:45');
      expect(formatDanmakuTimeOffset(125), '延后 02:05');
    });

    test('负 → 提前 MM:SS', () {
      expect(formatDanmakuTimeOffset(-45), '提前 00:45');
      expect(formatDanmakuTimeOffset(-125), '提前 02:05');
    });
  });
}
