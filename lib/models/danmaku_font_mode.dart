/// 弹幕字体三态（工作.md 第 4 点）：跟随系统 / 跟随 App / 自定义。
///
/// 弹幕实际生效字体族名由 [resolveDanmakuFontFamily] 现算（纯函数）：
/// - followSystem → null（canvas/Skia 回落系统默认字体，即跟随主题商店字体）；
/// - followApp → App 全局字体族名（可能为 null，表示 App 也跟随系统）；
/// - custom → 弹幕自定义字体族名。
library;

enum DanmakuFontMode {
  followSystem('跟随系统字体'),
  followApp('跟随App字体'),
  custom('自定义字体');

  final String label;
  const DanmakuFontMode(this.label);
}

/// 解析弹幕实际生效的字体族名（null = 跟随系统默认字体）。
///
/// 渲染时现算、不落盘中间态：切换 App 字体时，仅 followApp 模式受影响，
/// 其余模式解析结果不变（canvas 的 fontFamily 未变则不会清屏重绘）。
String? resolveDanmakuFontFamily({
  required DanmakuFontMode mode,
  required String? customFontFamily,
  required String? appFontFamily,
}) {
  switch (mode) {
    case DanmakuFontMode.followSystem:
      return null;
    case DanmakuFontMode.followApp:
      return appFontFamily;
    case DanmakuFontMode.custom:
      return customFontFamily;
  }
}
