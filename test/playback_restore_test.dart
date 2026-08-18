import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/playback_restore.dart';

/// 恢复进度阈值判定纯函数测试（v3 用户反馈：
/// 循环播放时"无限恢复已看完视频的进度" → 看完/起点不恢复）。
void main() {
  const duration = Duration(minutes: 10); // 10 分钟

  test('无进度 / 时长为 0 → 不恢复', () {
    expect(shouldRestorePosition(Duration.zero, Duration.zero), isFalse);
    expect(shouldRestorePosition(duration, Duration.zero), isFalse);
    expect(shouldRestorePosition(Duration.zero, const Duration(seconds: 1)),
        isFalse);
  });

  test('进度 ≥ 时长（已看完）→ 不恢复', () {
    expect(shouldRestorePosition(duration, duration), isFalse);
    expect(
        shouldRestorePosition(duration, duration + const Duration(seconds: 1)),
        isFalse);
  });

  test('进度 < 5% → 不恢复（几乎没看，从头播）', () {
    expect(shouldRestorePosition(duration, const Duration(seconds: 10)),
        isFalse); // 1.7%
    expect(
        shouldRestorePosition(duration, const Duration(seconds: 29)), isFalse); // 4.8%
    expect(
        shouldRestorePosition(duration, const Duration(seconds: 30)), isTrue); // 5.0% 边界
  });

  test('进度在 5% – 阈值之间 → 恢复', () {
    expect(shouldRestorePosition(duration, const Duration(minutes: 1)),
        isTrue); // 10%
    expect(shouldRestorePosition(duration, const Duration(minutes: 5)),
        isTrue); // 50%
    expect(
        shouldRestorePosition(
            duration, const Duration(minutes: 8, seconds: 30)),
        isTrue); // 85%
  });

  test('进度 ≥ 阈值（默认 90%）→ 不恢复（已看完）', () {
    expect(
        shouldRestorePosition(
            duration, const Duration(minutes: 9)), isFalse); // 90% 边界
    expect(
        shouldRestorePosition(
            duration, const Duration(minutes: 9, seconds: 30)),
        isFalse); // 95%
  });

  test('自定义阈值（已观看进度阈值设置）', () {
    // 阈值 95%：94% 恢复、95% 不恢复
    expect(
        shouldRestorePosition(
            duration,
            const Duration(minutes: 9, seconds: 24),
            maxRestoreRatio: 0.95),
        isTrue); // 94%
    expect(
        shouldRestorePosition(
            duration,
            const Duration(minutes: 9, seconds: 30),
            maxRestoreRatio: 0.95),
        isFalse); // 95%
    // 阈值 50%（极端设置）
    expect(
        shouldRestorePosition(
            duration, const Duration(minutes: 5), maxRestoreRatio: 0.5),
        isFalse);
    expect(
        shouldRestorePosition(
            duration, const Duration(minutes: 4), maxRestoreRatio: 0.5),
        isTrue);
  });
}
