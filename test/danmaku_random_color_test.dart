import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/danmaku_random_color.dart';

/// 随机渐变色纯函数测试：色轮分布、RGB 合法性、种子可复现、确定性推进。
void main() {
  group('hsvToRgb', () {
    test('基础色相点', () {
      expect(hsvToRgb(0, 1, 1), 0xFF0000); // 红
      expect(hsvToRgb(120, 1, 1), 0x00FF00); // 绿
      expect(hsvToRgb(240, 1, 1), 0x0000FF); // 蓝
    });
    test('灰阶（饱和度 0）', () {
      expect(hsvToRgb(0, 0, 1), 0xFFFFFF);
      expect(hsvToRgb(200, 0, 0.5), 0x808080);
    });
    test('色相越界环绕', () {
      expect(hsvToRgb(360, 1, 1), 0xFF0000); // 360 ≡ 0 红
      expect(hsvToRgb(-120, 1, 1), 0x0000FF); // -120 ≡ 240 蓝
    });
    test('输出始终为合法 24 位 RGB', () {
      for (var h = 0.0; h < 360; h += 7) {
        final rgb = hsvToRgb(h, 0.75, 0.92);
        expect(rgb, greaterThanOrEqualTo(0));
        expect(rgb, lessThanOrEqualTo(0xFFFFFF));
      }
    });
  });

  group('DanmakuColorWheel', () {
    test('种子相同 → 序列可复现（可单测/可回归）', () {
      final a = DanmakuColorWheel(seed: 42);
      final b = DanmakuColorWheel(seed: 42);
      for (var i = 0; i < 20; i++) {
        expect(a.nextColor(), b.nextColor());
      }
    });

    test('颜色分布覆盖多个色相区段（不聚集在起点附近）', () {
      final wheel = DanmakuColorWheel(seed: 7);
      // 按红/绿/蓝主导粗分三区（黄金角步进保证长序列覆盖整个色轮）
      var red = 0, green = 0, blue = 0;
      for (var i = 0; i < 60; i++) {
        final c = wheel.nextColor();
        final r = (c >> 16) & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = c & 0xFF;
        if (r >= g && r >= b) {
          red++;
        } else if (g >= b) {
          green++;
        } else {
          blue++;
        }
      }
      // 60 条在三个主导区都有分布（黄金角均匀性；漂移 ±15° 不破坏）
      expect(red, greaterThan(5));
      expect(green, greaterThan(5));
      expect(blue, greaterThan(5));
    });

    test('高饱和高明度（可读性约束：v ≥ 0.85）', () {
      final wheel = DanmakuColorWheel(seed: 1);
      for (var i = 0; i < 40; i++) {
        final c = wheel.nextColor();
        final r = (c >> 16) & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = c & 0xFF;
        // 明度 = max(r,g,b)/255 ≥ 0.85*255 ≈ 217（容差 2）
        final maxChannel = [r, g, b].reduce((a, b) => a > b ? a : b);
        expect(maxChannel, greaterThanOrEqualTo(215));
      }
    });

    test('sequence 计数推进', () {
      final wheel = DanmakuColorWheel(seed: 3);
      expect(wheel.sequence, 0);
      wheel.nextColor();
      wheel.nextColor();
      expect(wheel.sequence, 2);
    });
  });
}
