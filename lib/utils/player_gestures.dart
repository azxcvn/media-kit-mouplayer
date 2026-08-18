import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 双击手势判定结果
enum DoubleTapGesture {
  /// 切换播放/暂停
  pauseToggle,

  /// 快退
  seekBackward,

  /// 快进
  seekForward,
}

/// 根据双击横坐标 [dx]（相对宽度 [width]）与手势模式 [mode] 判定动作：
///
/// - [DoubleTapMode.pause]：任意位置都切换播放/暂停；
/// - [DoubleTapMode.seek]：左半屏快退、右半屏快进；
/// - [DoubleTapMode.mixed]：中央 40% 区域切换播放/暂停，
///   左右各 30% 快退/快进（"并非绝对中间，而是一个区域"）。
DoubleTapGesture classifyDoubleTap(
  double dx,
  double width,
  DoubleTapMode mode,
) {
  switch (mode) {
    case DoubleTapMode.pause:
      return DoubleTapGesture.pauseToggle;
    case DoubleTapMode.seek:
      return dx < width / 2
          ? DoubleTapGesture.seekBackward
          : DoubleTapGesture.seekForward;
    case DoubleTapMode.mixed:
      if (dx >= width * 0.3 && dx <= width * 0.7) {
        return DoubleTapGesture.pauseToggle;
      }
      return dx < width * 0.3
          ? DoubleTapGesture.seekBackward
          : DoubleTapGesture.seekForward;
  }
}

// ────────────────────────────────────────────────────────────
// 滑动手势数学（纯函数，可单测）
// ────────────────────────────────────────────────────────────

/// 水平滑动 seek：满屏宽度对应的 seek 秒数（对齐 PiliPlus 默认绝对档位 90 秒）
const double swipeSeekSecondsPerFullWidth = 90;

/// 每像素对应的 seek 毫秒数
double swipeSeekMsPerPixel(double screenWidth) {
  assert(screenWidth > 0);
  return swipeSeekSecondsPerFullWidth * 1000 / screenWidth;
}

/// 水平滑动后的目标播放位置：以 [start] 为起点，滑动 [dxPixels] 像素
/// （右滑为正 → 快进），钳制在 [0, duration]。
Duration swipeSeekTarget(
  Duration start,
  double dxPixels,
  double screenWidth,
  Duration duration,
) {
  final deltaMs = (swipeSeekMsPerPixel(screenWidth) * dxPixels).round();
  final totalMs = duration.inMilliseconds;
  final target = (start.inMilliseconds + deltaMs).clamp(0, totalMs);
  return Duration(milliseconds: target);
}

/// 音量滑动增量（0 – 100 刻度）：向上滑（dy 为负）音量增大；
/// [sensitivity] 为满屏滑动对应的量程倍率（默认 1.0 = 满屏走满 100）。
double volumeDeltaForSwipe(
  double dyPixels,
  double screenHeight,
  double sensitivity,
) {
  assert(screenHeight > 0);
  return -dyPixels / screenHeight * 100 * sensitivity;
}

/// 亮度滑动增量（0 – 1 刻度）：向上滑变亮。
double brightnessDeltaForSwipe(
  double dyPixels,
  double screenHeight,
  double sensitivity,
) {
  assert(screenHeight > 0);
  return -dyPixels / screenHeight * sensitivity;
}

/// 长按期间左右滑动的动态倍速档位（1.5 – 4.0，间隔 0.5，离散）
List<double> dynamicSpeedPresets() {
  final count =
      ((PlayerControlsSettings.maxDynamicSpeed -
                  PlayerControlsSettings.minDynamicSpeed) /
              PlayerControlsSettings.dynamicSpeedStep)
          .round() +
      1;
  return [
    for (var i = 0; i < count; i++)
      PlayerControlsSettings.minDynamicSpeed +
          i * PlayerControlsSettings.dynamicSpeedStep,
  ];
}

/// 动态调速：从 [startIndex] 档开始，横向滑动 [dxPixels] 像素后的目标档位索引。
///
/// 对齐 kt 项目算法：满屏宽度映射 [presetCount - 1] × 3.5 个档位跨度，
/// 即滑动一屏大约跨越 3.5 个档位跨度（每档 ~0.5x）。
int dynamicSpeedIndex(
  double dxPixels,
  double screenWidth,
  int startIndex,
  int presetCount,
) {
  assert(screenWidth > 0);
  assert(presetCount > 0);
  final range = presetCount - 1;
  final indexDelta = (dxPixels / screenWidth) * range * 3.5;
  return (startIndex + indexDelta.round()).clamp(0, range);
}

/// 取与 [speed] 最接近的档位索引（超出范围时钳制到边界）
int nearestSpeedPresetIndex(double speed, List<double> presets) {
  if (presets.isEmpty) return 0;
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < presets.length; i++) {
    final d = (presets[i] - speed).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}
