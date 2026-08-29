/// 弹幕条目纯数据模型（时间/模式/颜色/文本），来源为 B站 XML 等本地弹幕文件。
library;

/// 单条弹幕（对齐 B站 XML `<d p="time,mode,fontsize,color,...">` 的数据面）。
///
/// 纯数据类（无逻辑、无依赖，可跨 isolate 发送——解析在后台 isolate 完成，
/// 结果通过 `compute` 回传）。
class DanmakuEntry {
  /// 出现时间（秒，浮点）
  final double time;

  /// B站弹幕模式：1 = 右到左滚动、4 = 底部、5 = 顶部、6 = 逆向、
  /// 7 = 高级、8 = 代码、9 = BAS；渲染映射见服务层（非 4/5 一律按滚动，
  /// 对齐 Kazumi `player_item.dart` 的 `_danmakuItemType`）
  final int mode;

  /// 颜色（十进制 24 位 RGB，如 16777215 = 白色）
  final int color;

  /// 弹幕文本（已反转义、去除首尾空白）
  final String text;

  const DanmakuEntry({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });

  /// 所属秒桶（调度按秒分桶发射）
  int get timeSeconds => time.floor();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DanmakuEntry &&
          other.time == time &&
          other.mode == mode &&
          other.color == color &&
          other.text == text;

  @override
  int get hashCode => Object.hash(time, mode, color, text);
}
