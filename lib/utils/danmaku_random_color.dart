/// 随机渐变色纯函数（工作.md 弹幕第 4 点原创功能）：开启「随机渐变色」后
/// 忽略弹幕文件内颜色，所有弹幕按 HSV 色轮渐变随机着色。
///
/// 算法（原创，保证同屏相邻弹幕色差均匀、不撞色）：
/// - 色轮起点随机（每次会话不同），步进固定 137.5°（黄金角 ≈ 360° ×
///   (2 - φ) ≈ 137.507°）：相邻两条弹幕在色轮上错开黄金角，色相分布
///   最均匀、长时间滚动不重复段落（黄金角分割是自然界叶序排列的同款
///   均匀分布算法）；
/// - 随机漂移 ±15° 打乱可预测感（同一内容的连续弹幕颜色仍有区分）；
/// - 饱和度 65%–85%、明度 85%–100% 随机抖动：保持高可读性的同时带出
///   渐变层次（纯色轮会有塑料感）。
///
/// 纯函数（无状态、无 Flutter 依赖，可单测）：调用方持有推进状态
/// [DanmakuColorWheel]，逐条弹幕调用 [nextColor] 生成。
library;

import 'dart:math';

/// HSV → RGB（h 0–360 / s 0–1 / v 0–1 → 0xRRGGBB）
int hsvToRgb(double h, double s, double v) {
  final hh = ((h % 360) + 360) % 360;
  final c = v * s;
  final x = c * (1 - ((hh / 60) % 2 - 1).abs());
  final m = v - c;
  final (r1, g1, b1) = switch (hh) {
    < 60 => (c, x, 0.0),
    < 120 => (x, c, 0.0),
    < 180 => (0.0, c, x),
    < 240 => (0.0, x, c),
    < 300 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  final r = ((r1 + m) * 255).round().clamp(0, 255);
  final g = ((g1 + m) * 255).round().clamp(0, 255);
  final b = ((b1 + m) * 255).round().clamp(0, 255);
  return (r << 16) | (g << 8) | b;
}

/// 色轮推进器：随机起点 + 黄金角步进，逐条弹幕生成随机渐变色。
class DanmakuColorWheel {
  /// 黄金角（度）：相邻两条弹幕的色相差，色相分布最均匀
  static const double goldenAngle = 137.508;

  final Random _random;

  /// 当前色相（度）；构造时随机起点（非 final，逐条推进）
  double _hue = 0;

  int _sequence = 0;

  /// [seed] 可指定随机种子（单测可复现）；默认按时间随机
  DanmakuColorWheel({int? seed}) : _random = Random(seed) {
    _hue = _random.nextDouble() * 360;
  }

  /// 已生成的颜色数（调试/测试用）
  int get sequence => _sequence;

  /// 生成下一条弹幕的随机渐变色（0xRRGGBB）：
  /// 色相按黄金角推进 + ±15° 漂移，饱和度 0.65–0.85、明度 0.85–1.0 随机。
  int nextColor() {
    _sequence++;
    _hue = _hue + goldenAngle + (_random.nextDouble() * 30 - 15);
    final saturation = 0.65 + _random.nextDouble() * 0.2;
    final value = 0.85 + _random.nextDouble() * 0.15;
    return hsvToRgb(_hue, saturation, value);
  }
}
