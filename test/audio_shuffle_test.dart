import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/audio_shuffle.dart';

void main() {
  group('audioShuffleNextIndex（听视频随机播放，时间刻算法）', () {
    test('列表长度 1：恒返回 0', () {
      expect(
        audioShuffleNextIndex(
          listLength: 1,
          currentIndex: 0,
          now: DateTime(2026, 8, 22, 9, 30, 0),
        ),
        0,
      );
    });

    test('结果始终在 [0, listLength) 且不与当前曲目重复', () {
      for (var length = 2; length <= 12; length++) {
        for (var current = 0; current < length; current++) {
          for (var i = 0; i < 50; i++) {
            final now = DateTime(2026, 8, 22, 9, 30, i % 60, i * 7 % 1000);
            final next = audioShuffleNextIndex(
              listLength: length,
              currentIndex: current,
              now: now,
            );
            expect(next, inInclusiveRange(0, length - 1));
            expect(next, isNot(current), reason: '不应连续播放同一首');
          }
        }
      }
    });

    test('同一时刻结果确定（可复现），不同时刻通常不同', () {
      final t1 = DateTime(2026, 8, 22, 9, 30, 15, 123);
      final t2 = DateTime(2026, 8, 22, 9, 30, 15, 123);
      final r1 = audioShuffleNextIndex(
        listLength: 20,
        currentIndex: 0,
        now: t1,
      );
      final r2 = audioShuffleNextIndex(
        listLength: 20,
        currentIndex: 0,
        now: t2,
      );
      expect(r1, r2);

      // 不同时刻：用多个不同时刻抽样，至少出现一次不同结果
      var seenDifferent = false;
      for (var s = 0; s < 30; s++) {
        final now = DateTime(2026, 8, 22, 9, 30, s);
        final r = audioShuffleNextIndex(
          listLength: 20,
          currentIndex: 0,
          now: now,
        );
        if (r != r1) {
          seenDifferent = true;
          break;
        }
      }
      expect(seenDifferent, isTrue,
          reason: '不同时间刻应产生不同结果（才是「真正的随机」）');
    });

    test('与日期无关：只由当天时刻决定', () {
      final a = DateTime(2026, 8, 22, 10, 5, 3, 700);
      final b = DateTime(2030, 1, 1, 10, 5, 3, 700); // 不同日期、同一时刻
      final r1 = audioShuffleNextIndex(
        listLength: 9,
        currentIndex: 2,
        now: a,
      );
      final r2 = audioShuffleNextIndex(
        listLength: 9,
        currentIndex: 2,
        now: b,
      );
      expect(r1, r2);
    });

    test('分钟切换边界也稳定（跨分钟不异常）', () {
      // 23:59:59.999 → 00:00:00.000 不抛异常且结果合法
      final before = audioShuffleNextIndex(
        listLength: 7,
        currentIndex: 3,
        now: DateTime(2026, 8, 22, 23, 59, 59, 999),
      );
      final after = audioShuffleNextIndex(
        listLength: 7,
        currentIndex: 3,
        now: DateTime(2026, 8, 23, 0, 0, 0, 0),
      );
      expect(before, inInclusiveRange(0, 6));
      expect(after, inInclusiveRange(0, 6));
      expect(before, isNot(3));
      expect(after, isNot(3));
    });
  });
}
