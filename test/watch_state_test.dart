import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/watch_state.dart';

/// classifyWatchState / watchPercent 纯函数测试
void main() {
  group('classifyWatchState', () {
    test('无进度 → 未观看', () {
      expect(
        classifyWatchState(durationMs: 600000, progress: null, threshold: 0.95),
        WatchState.notWatched,
      );
    });

    test('进度为 0 → 未观看', () {
      expect(
        classifyWatchState(
          durationMs: 600000,
          progress: Duration.zero,
          threshold: 0.95,
        ),
        WatchState.notWatched,
      );
    });

    test('时长为 0 → 未观看', () {
      expect(
        classifyWatchState(
          durationMs: 0,
          progress: const Duration(seconds: 30),
          threshold: 0.95,
        ),
        WatchState.notWatched,
      );
    });

    test('进度 0 < p < 阈值 → 观看中', () {
      expect(
        classifyWatchState(
          durationMs: 600000,
          progress: const Duration(minutes: 5),
          threshold: 0.95,
        ),
        WatchState.watching,
      );
    });

    test('进度 >= 阈值 → 已看完', () {
      expect(
        classifyWatchState(
          durationMs: 600000,
          progress: const Duration(minutes: 10),
          threshold: 0.95,
        ),
        WatchState.watched,
      );
    });

    test('自定义阈值：80% 进度即已看完', () {
      expect(
        classifyWatchState(
          durationMs: 600000,
          progress: const Duration(minutes: 8),
          threshold: 0.8,
        ),
        WatchState.watched,
      );
    });

    test('自定义阈值：80% 进度但阈值 95% → 观看中', () {
      expect(
        classifyWatchState(
          durationMs: 600000,
          progress: const Duration(minutes: 8),
          threshold: 0.95,
        ),
        WatchState.watching,
      );
    });

    test('进度恰好等于阈值 → 已看完', () {
      expect(
        classifyWatchState(
          durationMs: 1000,
          progress: const Duration(milliseconds: 950),
          threshold: 0.95,
        ),
        WatchState.watched,
      );
    });
  });

  group('watchPercent', () {
    test('无进度 → 0', () {
      expect(watchPercent(durationMs: 600000, progress: null), 0);
    });

    test('一半进度 → 50', () {
      expect(
        watchPercent(
          durationMs: 600000,
          progress: const Duration(minutes: 5),
        ),
        50,
      );
    });

    test('超出时长钳制到 100', () {
      expect(
        watchPercent(
          durationMs: 600000,
          progress: const Duration(minutes: 11),
        ),
        100,
      );
    });
  });
}
