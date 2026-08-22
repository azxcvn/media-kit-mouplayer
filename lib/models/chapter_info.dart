import 'dart:ui';

/// 跳过片段类型（OP/ED/前情提要/制作人员/正片前段/下集预告）。
///
/// 颜色方案对齐参考项目（小喵 player / mpvRx 的 SkipSegmentType）：
/// 每个类型一个专属色，用于进度条色段标记与跳过胶囊底色，
/// 颜色透明度在绘制/UI 层再调整（见 PlayerSeekBar / ChapterSkipChip）。
enum ChapterSkipType {
  intro('跳过片头', Color(0xFFFF7A00)),
  recap('跳过前情提要', Color(0xFF2F80FF)),
  outro('跳过片尾', Color(0xFFE05666)),
  credits('跳过制作人员', Color(0xFFA64DFF)),
  coldOpen('跳过正片前段', Color(0xFFFFB300)),
  preview('跳过下集预告', Color(0xFF00D4C7));

  /// 胶囊按钮文案（如「跳过片头」）
  final String label;

  /// 类型专属色（进度条色段 / 胶囊底色）
  final Color color;

  const ChapterSkipType(this.label, this.color);
}

/// 单个章节（来自 mpv 的 chapter-list 子属性）。
class ChapterInfo {
  /// 章节标题（可能为空串）
  final String title;

  /// 章节起始时间（秒）
  final double startSeconds;

  const ChapterInfo({required this.title, required this.startSeconds});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterInfo &&
          other.title == title &&
          other.startSeconds == startSeconds;

  @override
  int get hashCode => Object.hash(title, startSeconds);
}

/// 可跳过片段（章节关键词检测派生的 OP/ED/预告等时间段）。
class SkipSegment {
  final ChapterSkipType type;

  /// 片段起始时间（秒）
  final double startSeconds;

  /// 片段结束时间（秒，= 下一章节起点或视频时长）
  final double endSeconds;

  const SkipSegment({
    required this.type,
    required this.startSeconds,
    required this.endSeconds,
  });

  /// 有效片段：时长必须 > 1 秒（过短没有跳过意义）
  bool get isValid => endSeconds > startSeconds + 1.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkipSegment &&
          other.type == type &&
          other.startSeconds == startSeconds &&
          other.endSeconds == endSeconds;

  @override
  int get hashCode => Object.hash(type, startSeconds, endSeconds);
}
