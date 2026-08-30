/// 弹幕集数匹配纯函数（切集自动匹配弹幕，工作.md 第 7 点）：
/// 从视频文件名提取集数，再在自动匹配缓存里找到对应集。
///
/// 纯函数（无状态、无 Flutter 依赖），逻辑对齐参考项目 小喵player 的
/// `DanmakuAutoMatchCache.kt`。
library;

import 'package:moumou/models/dandan_models.dart';

/// 从视频文件名提取集数（去扩展名后按多套规则依次匹配）。
///
/// 支持：`01.mkv` / `第01话` / `S01E01` / `EP01` /
/// `[Group] Anime - 01 [1080p].mkv` / `Anime_12.5.mkv` 等。
/// 无法识别返回 null。
double? extractEpisodeNumber(String fileName) {
  final name = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;

  // S01E01（季 + 集，取集）
  final sxxExx = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(name);
  if (sxxExx != null) return double.tryParse(sxxExx.group(2)!);

  // 第01话 / 第01集 / 第01回
  final di = RegExp(r'第\s*(\d+(?:\.\d+)?)\s*[话集回話]').firstMatch(name);
  if (di != null) return double.tryParse(di.group(1)!);

  // EP01 / ep01
  final ep = RegExp(r'[Ee][Pp]\s*(\d+(?:\.\d+)?)').firstMatch(name);
  if (ep != null) return double.tryParse(ep.group(1)!);

  // 末尾集数（前有分隔符，可带 v2 修正与 [1080p]/【1080p】等后缀）
  final trailing = RegExp(
    r'[\[【\s\-_#](\d+(?:\.\d+)?)(?:[vV]\d+)?'
    r'(?:\s*(?:\[[^\]]*\]|【[^】]*】|[\]】]))?\s*$',
  ).firstMatch(name);
  if (trailing != null) return double.tryParse(trailing.group(1)!);

  // 开头集数（`01 - Title` 格式）
  final leading = RegExp(r'^(\d+(?:\.\d+)?)\s*[-–—_\s]').firstMatch(name);
  if (leading != null) return double.tryParse(leading.group(1)!);

  // 纯数字文件名
  final pure = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(name);
  if (pure != null) return double.tryParse(pure.group(1)!);

  return null;
}

/// 从集标题提取集数：优先按文件名规则，失败退回「标题里出现的第一个数字」。
double? extractEpisodeNumberFromTitle(String episodeTitle) {
  final direct = extractEpisodeNumber(episodeTitle);
  if (direct != null) return direct;
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(episodeTitle);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// 按集数在集列表中找到匹配集：先按标题集数精确匹配，失败按「集数取整 →
/// 数组下标」回退（第 N 集 = 列表第 N 项，应对标题无集数的情况）。
DandanEpisode? findMatchingEpisode(
  List<DandanEpisode> episodes,
  double episodeNumber,
) {
  for (final ep in episodes) {
    final num = extractEpisodeNumberFromTitle(ep.episodeTitle);
    if (num != null && (num - episodeNumber).abs() < 0.001) return ep;
  }
  final index = episodeNumber.toInt() - 1;
  if (index >= 0 && index < episodes.length) return episodes[index];
  return null;
}
