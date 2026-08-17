import 'package:moumou/models/player_action.dart';

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
