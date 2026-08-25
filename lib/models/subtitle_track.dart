import 'package:flutter/foundation.dart';

/// 字幕轨道（工作.md 阶段1 第 3 点）：播放器当前媒体可用的字幕轨道。
///
/// 数据来自 mpv `track-list` 子属性（内嵌字幕）或 `sub-add` 添加的外部字幕；
/// [external] 为 true 表示外挂字幕（切集后不会自动存在，需重新添加）。
@immutable
class SubtitleTrack {
  /// mpv 轨道 id（`track-list/$i/id`，字符串形式）
  final String id;

  /// 轨道标题（`title` 属性，可能为空）
  final String? title;

  /// 语言代码（`lang` 属性，可能为空）
  final String? language;

  /// 是否为外挂字幕（通过 `sub-add` 添加；切集后消失需重新添加）
  final bool external;

  /// 字幕编码格式（`codec` 属性：srt / ass / ssa / webvtt 等，可能为空）
  final String? codec;

  /// 字幕源路径（mpv `external-filename`，外挂字幕为文件绝对路径；内嵌为 null）。
  /// 用于切集重新添加外挂字幕后按路径恢复主/次勾选（轨道 id 重开会变）。
  final String? sourcePath;

  const SubtitleTrack({
    required this.id,
    this.title,
    this.language,
    this.external = false,
    this.codec,
    this.sourcePath,
  });

  /// 是否为内嵌样式字幕（ASS / SSA）：
  /// 这类字幕自带样式与字体，默认应尊重其内嵌样式而不是强制覆盖
  /// （工作.md 阶段1 第 3 点：内嵌字幕应启用自带样式与字体）。
  bool get isStyled => _isStyledSubtitle(codec);

  /// 展示名：优先标题，其次语言，最后回退「轨道 N」
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    if (language != null && language!.trim().isNotEmpty) return language!.trim();
    return '轨道 $id';
  }
}

/// 判断字幕编码是否为内嵌样式字幕（ASS/SSA）。null 视为普通文本字幕。
bool _isStyledSubtitle(String? codec) {
  if (codec == null) return false;
  final c = codec.toLowerCase();
  return c.contains('ass') || c.contains('ssa');
}

/// 字幕轨道在面板中的显示名（纯函数，可单测）。
/// 返回 `displayTitle` + 外挂标记 + 格式后缀，如「简体中文 · 外挂 · ass」。
String subtitleTrackLabel(SubtitleTrack track) {
  final parts = <String>[track.displayTitle];
  if (track.external) parts.add('外挂');
  if (track.codec != null && track.codec!.trim().isNotEmpty) {
    parts.add(track.codec!.trim());
  }
  return parts.join(' · ');
}

/// 支持的外挂字幕扩展名（参考小喵 player `isSupportedSubtitleFormat`）。
const Set<String> kSupportedSubtitleExtensions = {
  'srt', 'ass', 'ssa', 'sub', 'vtt', 'lrc', 'sbv', 'smi', 'pjs',
  'psb', 'rt', 'aqt', 'mpl2', 'txt', 'dvd', 'idx', 'sup',
};

/// 判断文件名是否为支持的字幕格式（纯函数，可单测；大小写不敏感）。
bool isSupportedSubtitleFile(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  final ext = filename.substring(dot + 1).toLowerCase();
  return kSupportedSubtitleExtensions.contains(ext);
}

/// 支持的自导入字体扩展名（.ttf / .otf / .ttc）。
const Set<String> kFontExtensions = {'ttf', 'otf', 'ttc', 'otc'};

/// 判断文件名是否为字体文件（自建字体选择器过滤用；大小写不敏感）。
bool isFontFile(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  final ext = filename.substring(dot + 1).toLowerCase();
  return kFontExtensions.contains(ext);
}

/// 字幕对齐（mpv `sub-align-x`）：水平位置三选。
enum SubtitleAlign {
  center('center', '居中'),
  left('left', '左对齐'),
  right('right', '右对齐');

  /// mpv 属性值
  final String mpvValue;
  final String label;
  const SubtitleAlign(this.mpvValue, this.label);

  static SubtitleAlign byMpvValue(String v) => switch (v) {
        'left' => SubtitleAlign.left,
        'right' => SubtitleAlign.right,
        _ => SubtitleAlign.center,
      };
}

/// 字幕描边模式（mpv `sub-border-style`）：决定立体感的呈现方式。
/// 面板「描边模式」三选一，并据此提示应该调节哪个颜色/粗细。
enum SubtitleBorderStyle {
  /// 无描边（flat：实心边缘，仅文字色）
  none('flat', '无'),

  /// 经典细描边（outline）
  outline('outline', '描边'),

  /// 字幕后方背景框（box）
  box('box', '背景框');

  /// mpv 属性值
  final String mpvValue;
  final String label;
  const SubtitleBorderStyle(this.mpvValue, this.label);

  static SubtitleBorderStyle byMpvValue(String v) => switch (v) {
        'outline' => SubtitleBorderStyle.outline,
        'box' => SubtitleBorderStyle.box,
        _ => SubtitleBorderStyle.none,
      };
}

/// 字幕预设颜色（mpv `sub-color`，工作.md 阶段1 第 3 点样式项）。
class SubtitlePresetColor {
  final String label;
  final String hex;

  const SubtitlePresetColor(this.label, this.hex);

  /// 文字颜色常用预设（3~4 种常用色，对齐小喵 player 需求）
  static const List<SubtitlePresetColor> textPresets = [
    SubtitlePresetColor('白色', '#FFFFFF'),
    SubtitlePresetColor('黄色', '#FFEB3B'),
    SubtitlePresetColor('青色', '#4DD0E1'),
    SubtitlePresetColor('绿色', '#81C784'),
  ];

  /// 描边颜色常用预设（黑色、白色、黄色，去除了红色）
  static const List<SubtitlePresetColor> borderPresets = [
    SubtitlePresetColor('黑色', '#000000'),
    SubtitlePresetColor('白色', '#FFFFFF'),
    SubtitlePresetColor('黄色', '#FFEB3B'),
  ];

  /// 背景颜色常用预设（对齐小喵 player 需求）
  static const List<SubtitlePresetColor> backPresets = [
    SubtitlePresetColor('半透明黑', '#80000000'),
    SubtitlePresetColor('纯黑', '#FF000000'),
    SubtitlePresetColor('半透明白', '#80FFFFFF'),
    SubtitlePresetColor('半透明蓝', '#801A2332'),
  ];

  /// 兼容旧引用
  static const List<SubtitlePresetColor> presets = textPresets;

  static SubtitlePresetColor byHex(String hex) {
    final upper = hex.toUpperCase();
    for (final p in presets) {
      if (p.hex == upper) return p;
    }
    return presets.first;
  }
}

/// 颜色 RGBA 分量（各 0–255）。用于字幕颜色滑杆调节（工作.md 阶段1 第 3 点，
/// 需求：像小喵 player 一样通过滑块调 R/G/B/A 获得任意颜色）。
typedef SubtitleRgba = ({int r, int g, int b, int a});

/// 把 RGBA 分量格式化为 mpv 颜色的十六进制串：
/// - alpha == 255（不透明）→ `#RRGGBB`（6 位，保证兼容性）；
/// - alpha < 255 → `#AARRGGBB`（8 位，mpv 的 alpha 通道在前）。
/// 分量为 clamp 到 0–255 后取整。
String rgbaToMpvColor(SubtitleRgba c) {
  final r = c.r.clamp(0, 255);
  final g = c.g.clamp(0, 255);
  final b = c.b.clamp(0, 255);
  final a = c.a.clamp(0, 255);
  String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  if (a == 255) return '#${two(r)}${two(g)}${two(b)}';
  return '#${two(a)}${two(r)}${two(g)}${two(b)}';
}

/// 把 mpv 颜色串解析为 RGBA 分量。支持 `#RRGGBB`（不透明）与 `#AARRGGBB`
/// （8 位，alpha 在前）。非法输入回退为纯黑不透明。
SubtitleRgba mpvColorToRgba(String hex) {
  final h = hex.replaceAll('#', '').toUpperCase();
  int val(int start, int len) {
    final seg = h.substring(start, start + len);
    return int.tryParse(seg, radix: 16) ?? 0;
  }

  switch (h.length) {
    case 6:
      return (r: val(0, 2), g: val(2, 2), b: val(4, 2), a: 255);
    case 8:
      return (a: val(0, 2), r: val(2, 2), g: val(4, 2), b: val(6, 2));
    default:
      return (r: 0, g: 0, b: 0, a: 255);
  }
}
