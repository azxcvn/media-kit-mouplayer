import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/services/danmaku_scheduler.dart';

DanmakuEntry _e(double time, String text) =>
    DanmakuEntry(time: time, mode: 1, color: 0xFFFFFF, text: text);

/// 弹幕调度器测试：秒桶前向补发 / 首个 tick 锚定 / seek 跳变检测 /
/// 代数失效 / 微幅回抖不重发。
void main() {
  group('feed / hasDanmaku / danmakuCount', () {
    test('按秒分桶，计数正确', () {
      final s = DanmakuScheduler();
      expect(s.hasDanmaku, isFalse);
      s.feed([_e(1.2, 'a'), _e(1.8, 'b'), _e(2.0, 'c')]);
      expect(s.hasDanmaku, isTrue);
      expect(s.danmakuCount, 3);
    });
  });

  group('onTick（1x 正常推进）', () {
    test('首个 tick 只发当前桶并锚定（恢复到中途不倾倒历史）', () {
      final s = DanmakuScheduler();
      s.feed([_e(0.5, 'x'), _e(100.0, 'a'), _e(100.9, 'b'), _e(101.5, 'c')]);
      // 首个 tick 在 100.4s：只发第 100 秒桶（a、b），不回放 0.5s 的 x
      final r = s.onTick(const Duration(milliseconds: 100400), 1.0);
      expect(r.seeked, isFalse);
      expect(r.entries.map((e) => e.text).toList(), ['a', 'b']);
    });

    test('后续 tick 前向补发 (上一秒, 当前秒]（每桶恰发一次）', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 10; i++) _e(i + 0.5, 'd$i')]);
      expect(s.onTick(const Duration(milliseconds: 500), 1.0).entries,
          [_e(0.5, 'd0')]);
      expect(s.onTick(const Duration(milliseconds: 1500), 1.0).entries,
          [_e(1.5, 'd1')]);
      expect(s.onTick(const Duration(milliseconds: 2500), 1.0).entries,
          [_e(2.5, 'd2')]);
    });

    test('计时抖动跨秒不丢桶：tick 间隔 > 1s 时补发中间秒', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 10; i++) _e(i + 0.5, 'd$i')]);
      // 首个 tick 落在 0.9s（发 d0），下一个 tick 直接跳到 3.0s：
      // 补发 (0, 3] → d1、d2、d3（Kazumi 只发当前桶会丢 d1、d2）
      expect(s.onTick(const Duration(milliseconds: 900), 1.0).entries,
          [_e(0.5, 'd0')]);
      final r = s.onTick(const Duration(milliseconds: 3000), 1.0);
      expect(r.seeked, isFalse);
      expect(r.entries.map((e) => e.text).toList(), ['d1', 'd2', 'd3']);
    });

    test('空桶 tick 返回空列表（不 seek）', () {
      final s = DanmakuScheduler();
      s.feed([_e(1.0, 'a')]);
      s.onTick(const Duration(milliseconds: 1500), 1.0); // 发出 a 并锚定 1
      final r = s.onTick(const Duration(milliseconds: 2500), 1.0);
      expect(r.entries, isEmpty);
      expect(r.seeked, isFalse);
    });
  });

  group('onTick（高倍速）', () {
    test('4x 下一 tick 跨 4 秒：全部补发不丢', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 20; i++) _e(i + 0.5, 'd$i')]);
      s.onTick(const Duration(milliseconds: 500), 4.0); // 锚定 0，发 d0
      final r = s.onTick(const Duration(milliseconds: 4500), 4.0); // 跨到 4s
      expect(r.seeked, isFalse);
      expect(r.entries.map((e) => e.text).toList(), ['d1', 'd2', 'd3', 'd4']);
    });
  });

  group('onTick（seek 检测）', () {
    test('正向大跳（1x 下 +30s）→ seeked + 代数失效 + 不发射', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 60; i++) _e(i + 0.5, 'd$i')]);
      final genBefore = s.generation;
      s.onTick(const Duration(milliseconds: 500), 1.0);
      final r = s.onTick(const Duration(milliseconds: 30500), 1.0);
      expect(r.seeked, isTrue);
      expect(r.entries, isEmpty);
      expect(s.generation, genBefore + 1);
      // seek 后下一 tick 补发落点秒起的弹幕（锚点 = 落点秒 - 1，内容不丢）
      final r2 = s.onTick(const Duration(milliseconds: 31500), 1.0);
      expect(r2.seeked, isFalse);
      expect(r2.entries.map((e) => e.text).toList(), ['d30', 'd31']);
    });

    test('回退大跳（-30s）→ seeked', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 60; i++) _e(i + 0.5, 'd$i')]);
      s.onTick(const Duration(milliseconds: 50000), 1.0);
      final r = s.onTick(const Duration(milliseconds: 20000), 1.0);
      expect(r.seeked, isTrue);
      expect(r.entries, isEmpty);
    });

    test('微幅回抖（未达阈值）不判 seek、不重发', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 60; i++) _e(i + 0.5, 'd$i')]);
      s.onTick(const Duration(milliseconds: 10500), 1.0); // 发 d10，锚定 10
      // 回抖 0.5s（阈值 2s 内）：不 seek、不发（锚点不回退）
      final r = s.onTick(const Duration(milliseconds: 10000), 1.0);
      expect(r.seeked, isFalse);
      expect(r.entries, isEmpty);
      // 再前进：从锚定 10 继续补发（10 秒桶不重复发）
      final r2 = s.onTick(const Duration(milliseconds: 11500), 1.0);
      expect(r2.entries.map((e) => e.text).toList(), ['d11']);
    });

    test('阈值内正向小步进（1x 下 +1.9s）不判 seek，按补发处理', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 60; i++) _e(i + 0.5, 'd$i')]);
      s.onTick(const Duration(milliseconds: 500), 1.0);
      // 期望位移 1s + 阈值 2s = 3s 内不算 seek：2.9s 位移 → 补发 d1、d2
      final r = s.onTick(const Duration(milliseconds: 2900), 1.0);
      expect(r.seeked, isFalse);
      expect(r.entries.map((e) => e.text).toList(), ['d1', 'd2']);
    });
  });

  group('reset / invalidate（代数失效）', () {
    test('reset 清桶 + 重置锚点 + 代数自增', () {
      final s = DanmakuScheduler();
      s.feed([_e(1.0, 'a')]);
      final gen = s.generation;
      s.onTick(const Duration(milliseconds: 1500), 1.0);
      s.reset();
      expect(s.hasDanmaku, isFalse);
      expect(s.generation, gen + 1);
      // 重置后首个 tick 重新锚定（空桶无发射）
      final r = s.onTick(const Duration(milliseconds: 1500), 1.0);
      expect(r.entries, isEmpty);
    });

    test('invalidate 仅作废在途回调，保留秒桶', () {
      final s = DanmakuScheduler();
      s.feed([_e(1.0, 'a')]);
      final gen = s.generation;
      s.invalidate();
      expect(s.generation, gen + 1);
      expect(s.hasDanmaku, isTrue); // 桶还在
    });
  });

  group('isSeekJump（位置流实时 seek 检测）', () {
    test('正常前进（1x，位移 ≈ 倍速 × 间隔）→ 非跳变', () {
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(milliseconds: 10150),
          elapsedMs: 150,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('高倍速正常前进（位移 = 4 × 间隔）→ 非跳变', () {
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(milliseconds: 10800),
          elapsedMs: 200,
          rate: 4.0,
        ),
        isFalse,
      );
    });

    test('主 isolate 卡顿事件迟到（墙钟间隔同步变大）→ 非跳变', () {
      // 1x 下事件间隔 2s（卡顿），位移 2s：期望位移 = 2s ≥ 实际位移
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(seconds: 12),
          elapsedMs: 2000,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('回退超阈值（1s）→ 跳变；微幅回抖 → 非跳变', () {
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 30),
          currentPosition: const Duration(seconds: 28),
          elapsedMs: 100,
          rate: 1.0,
        ),
        isTrue,
      );
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 30),
          currentPosition: const Duration(milliseconds: 29500),
          elapsedMs: 100,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('正向跳变超出期望 + 松弛量 → 跳变', () {
      // 进度条松手：+30s（事件间隔仅 100ms）
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(seconds: 40),
          elapsedMs: 100,
          rate: 1.0,
        ),
        isTrue,
      );
      // 前向微抖（+0.5s）→ 非跳变
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(milliseconds: 10500),
          elapsedMs: 100,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('暂停期间位置不变 → 非跳变（恢复后 seek → 跳变）', () {
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 30),
          currentPosition: const Duration(seconds: 30),
          elapsedMs: 5000,
          rate: 1.0,
        ),
        isFalse,
      );
      expect(
        DanmakuScheduler.isSeekJump(
          previousPosition: const Duration(seconds: 30),
          currentPosition: const Duration(seconds: 45),
          elapsedMs: 100,
          rate: 1.0,
        ),
        isTrue,
      );
    });
  });

  group('notifySeeked（实时 seek 通知）', () {
    test('代数失效 + 锚点对齐到落点秒 - 1（下一 tick 补发落点秒）', () {
      final s = DanmakuScheduler();
      s.feed([for (var i = 0; i < 60; i++) _e(i + 0.5, 'd$i')]);
      s.onTick(const Duration(milliseconds: 500), 1.0); // 锚定 0，发 d0
      final genBefore = s.generation;
      // 跳到 30.4s（进度条松手，位置流实时通知）
      s.notifySeeked(const Duration(milliseconds: 30400));
      expect(s.generation, genBefore + 1);
      // 下一 tick（30.9s → 31.9s）：补发落点秒 30 与 31
      final r = s.onTick(const Duration(milliseconds: 31900), 1.0);
      expect(r.seeked, isFalse);
      expect(r.entries.map((e) => e.text).toList(), ['d30', 'd31']);
    });
  });
}
