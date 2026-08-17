import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
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
}
