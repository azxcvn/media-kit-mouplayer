import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/pip_aspect.dart';

/// pipAspectRatio 纯函数测试：画中画宽高比（gcd 约分 + 0.5–2.39 限制）
void main() {
  test('视频尺寸未知 → 回退 16:9', () {
    expect(pipAspectRatio(0, 0), (width: 16, height: 9));
    expect(pipAspectRatio(-1, 100), (width: 16, height: 9));
    expect(pipAspectRatio(1920, 0), (width: 16, height: 9));
  });

  test('自定义回退比例', () {
    expect(
      pipAspectRatio(0, 0, fallbackWidth: 1, fallbackHeight: 1),
      (width: 1, height: 1),
    );
  });

  test('1080p 约分为 16:9', () {
    expect(pipAspectRatio(1920, 1080), (width: 16, height: 9));
  });

  test('720p 约分为 16:9', () {
    expect(pipAspectRatio(1280, 720), (width: 16, height: 9));
  });

  test('竖屏视频约分为 9:16', () {
    expect(pipAspectRatio(1080, 1920), (width: 9, height: 16));
  });

  test('非标准尺寸按 gcd 约分（如 3:2）', () {
    expect(pipAspectRatio(1500, 1000), (width: 3, height: 2));
  });

  test('超宽屏（32:9）钳制到 2.39:1', () {
    expect(pipAspectRatio(5120, 1440), (width: 239, height: 100));
  });

  test('超窄屏（1:4）钳制到 1:2', () {
    expect(pipAspectRatio(1080, 4320), (width: 1, height: 2));
  });
}
