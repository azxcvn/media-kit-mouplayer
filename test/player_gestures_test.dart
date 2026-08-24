import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/utils/player_gestures.dart';

void main() {
  const w = 800.0;

  test('暂停模式：任意位置双击都切换播放/暂停', () {
    expect(
      classifyDoubleTap(0, w, DoubleTapMode.pause),
      DoubleTapGesture.pauseToggle,
    );
    expect(
      classifyDoubleTap(400, w, DoubleTapMode.pause),
      DoubleTapGesture.pauseToggle,
    );
    expect(
      classifyDoubleTap(799, w, DoubleTapMode.pause),
      DoubleTapGesture.pauseToggle,
    );
  });

  test('进退模式：左半屏快退，右半屏快进', () {
    expect(
      classifyDoubleTap(0, w, DoubleTapMode.seek),
      DoubleTapGesture.seekBackward,
    );
    expect(
      classifyDoubleTap(399, w, DoubleTapMode.seek),
      DoubleTapGesture.seekBackward,
    );
    expect(
      classifyDoubleTap(400, w, DoubleTapMode.seek),
      DoubleTapGesture.seekForward,
    );
    expect(
      classifyDoubleTap(799, w, DoubleTapMode.seek),
      DoubleTapGesture.seekForward,
    );
  });

  test('混合模式：中央 40% 区域暂停，两侧各 30% 进退', () {
    // 左 30%：快退
    expect(
      classifyDoubleTap(100, w, DoubleTapMode.mixed),
      DoubleTapGesture.seekBackward,
    );
    // 0.3w 边界（含）→ 暂停
    expect(
      classifyDoubleTap(240, w, DoubleTapMode.mixed),
      DoubleTapGesture.pauseToggle,
    );
    // 中央任意位置 → 暂停
    expect(
      classifyDoubleTap(400, w, DoubleTapMode.mixed),
      DoubleTapGesture.pauseToggle,
    );
    // 0.7w 边界（含）→ 暂停
    expect(
      classifyDoubleTap(560, w, DoubleTapMode.mixed),
      DoubleTapGesture.pauseToggle,
    );
    // 右 30%：快进
    expect(
      classifyDoubleTap(600, w, DoubleTapMode.mixed),
      DoubleTapGesture.seekForward,
    );
  });

  // ── 水平滑动 seek ──────────────────────────────────────

  test('滑动 seek 灵敏度：满屏宽度 = 90 秒', () {
    // 800px 宽屏幕：每像素 90 * 1000 / 800 = 112.5ms
    expect(swipeSeekMsPerPixel(800), closeTo(112.5, 0.001));
    // 宽屏（如 2400px）：每像素 37.5ms
    expect(swipeSeekMsPerPixel(2400), closeTo(37.5, 0.001));
  });

  test('滑动 seek 目标：右滑快进，左滑快退，越界钳制', () {
    const duration = Duration(minutes: 10); // 600_000ms
    const start = Duration(minutes: 2); // 120_000ms
    // 右滑 200px：+200 * 112.5 = +22.5s
    expect(
      swipeSeekTarget(start, 200, w, duration),
      const Duration(milliseconds: 120000 + 22500),
    );
    // 左滑 200px：-22.5s
    expect(
      swipeSeekTarget(start, -200, w, duration),
      const Duration(milliseconds: 120000 - 22500),
    );
    // 大幅右滑钳制到片尾
    expect(
      swipeSeekTarget(start, 99999, w, duration),
      duration,
    );
    // 大幅左滑钳制到 0
    expect(swipeSeekTarget(start, -99999, w, duration), Duration.zero);
    // 从片头右滑
    expect(
      swipeSeekTarget(Duration.zero, 100, w, duration),
      const Duration(milliseconds: 11250),
    );
  });

  // ── 音量 / 亮度 ────────────────────────────────────────

  test('音量增量：满屏上滑（灵敏度 1.0）走满 0 – 100', () {
    // 向上滑满一屏：dy = -height → +100 * 1.0 = +100
    expect(volumeDeltaForSwipe(-800, 800, 1.0), closeTo(100, 0.001));
    // 向下滑满一屏：-100
    expect(volumeDeltaForSwipe(800, 800, 1.0), closeTo(-100, 0.001));
    // 灵敏度 2.0：翻倍
    expect(volumeDeltaForSwipe(-400, 800, 2.0), closeTo(100, 0.001));
    // 灵敏度 0.5：减半
    expect(volumeDeltaForSwipe(-800, 800, 0.5), closeTo(50, 0.001));
  });

  test('亮度增量：满屏上滑（灵敏度 1.0）走满 0 – 1', () {
    expect(brightnessDeltaForSwipe(-800, 800, 1.0), closeTo(1.0, 0.001));
    expect(brightnessDeltaForSwipe(800, 800, 1.0), closeTo(-1.0, 0.001));
    expect(brightnessDeltaForSwipe(-400, 800, 2.0), closeTo(1.0, 0.001));
    expect(brightnessDeltaForSwipe(-800, 800, 0.5), closeTo(0.5, 0.001));
  });

  // ── 长按动态调速 ───────────────────────────────────────

  test('动态倍速档位：1.5 – 4.0 间隔 0.5，共 6 档', () {
    expect(dynamicSpeedPresets(), [1.5, 2.0, 2.5, 3.0, 3.5, 4.0]);
  });

  test('动态调速索引：满屏右滑跨越约 6 个满区间跨度（1/6 屏扫完满区间）', () {
    // 6 档 → 5 个跨度；满屏右滑 → +5 * 6.0 = +30 → 钳制到 5（工作.md 阶段1 第 4 点）
    expect(dynamicSpeedIndex(800, 800, 0, 6), 5);
    // 满屏左滑：从 5 → -30 → 0
    expect(dynamicSpeedIndex(-800, 800, 5, 6), 0);
    // 1/6 屏宽（≈133.33px）从 0 档即可扫完满区间 → +5 * 6 * (1/6) = +5 → 5 档（4.0x）
    expect(dynamicSpeedIndex(800 / 6, 800, 0, 6), 5);
    // 小幅滑动（1/10 屏）：+0.1 * 5 * 6 = +3 → 从 0 到 3 档（3.0x）
    expect(dynamicSpeedIndex(80, 800, 0, 6), 3);
    // 越界钳制
    expect(dynamicSpeedIndex(99999, 800, 0, 6), 5);
    expect(dynamicSpeedIndex(-99999, 800, 3, 6), 0);
    // 不动：保持原档
    expect(dynamicSpeedIndex(0, 800, 3, 6), 3);
  });

  test('最近档位索引：设置值映射到最近档位并钳制边界', () {
    final presets = dynamicSpeedPresets();
    expect(nearestSpeedPresetIndex(2.0, presets), 1);
    expect(nearestSpeedPresetIndex(2.4, presets), 2); // 2.4 → 2.5
    expect(nearestSpeedPresetIndex(2.6, presets), 2); // 2.6 → 2.5
    expect(nearestSpeedPresetIndex(1.0, presets), 0); // 低于下限 → 1.5
    expect(nearestSpeedPresetIndex(9.0, presets), 5); // 高于上限 → 4.0
  });

  test('设置默认值约束与动态档位范围一致', () {
    final s = PlayerControlsSettings.instance;
    expect(s.longPressSpeed, 2.0);
    expect(
      s.longPressSpeed,
      inInclusiveRange(
        PlayerControlsSettings.minLongPressSpeed,
        PlayerControlsSettings.maxLongPressSpeed,
      ),
    );
    expect(
      dynamicSpeedPresets().first,
      PlayerControlsSettings.minDynamicSpeed,
    );
    expect(
      dynamicSpeedPresets().last,
      PlayerControlsSettings.maxDynamicSpeed,
    );
  });
}
