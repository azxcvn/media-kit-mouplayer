/// 画中画宽高比计算（纯函数，可单测）。
///
/// 参考 kt 项目 `PipHelper.kt`（fam4k007 小牛播放器）：
/// - 视频尺寸未知（≤ 0）→ 回退 16:9；
/// - 宽高比限制在 0.5 – 2.39（Android PiP 系统接受范围），超宽/超窄
///   分别钳制到 2.39:1 与 1:2；
/// - 范围内用最大公约数约分（Kazumi `getPIPAspectSize` 同款），
///   避免把 1920×1080 这类大数直接传给 `Rational`。
({int width, int height}) pipAspectRatio(
  int videoWidth,
  int videoHeight, {
  int fallbackWidth = 16,
  int fallbackHeight = 9,
}) {
  if (videoWidth <= 0 || videoHeight <= 0) {
    return (width: fallbackWidth, height: fallbackHeight);
  }
  final ratio = videoWidth / videoHeight;
  if (ratio > 2.39) return (width: 239, height: 100); // 2.39:1
  if (ratio < 0.5) return (width: 1, height: 2); // 1:2
  final g = _gcd(videoWidth, videoHeight);
  return (width: videoWidth ~/ g, height: videoHeight ~/ g);
}

int _gcd(int a, int b) {
  var x = a;
  var y = b;
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x;
}
