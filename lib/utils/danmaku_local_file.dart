/// 同名弹幕文件查找纯函数（9 种命名规则，对齐 mpv-android-anime4k 的
/// `DanmakuManager.findDanmakuFile`：只查视频同目录、不递归）。
library;

/// 视频同目录下的同名弹幕候选文件名（按优先级从高到低，共 9 种）。
///
/// [videoNameWithoutExt] 为视频文件名去掉扩展名（如 `EP01`）。
List<String> danmakuCandidateNames(String videoNameWithoutExt) => [
      '$videoNameWithoutExt.xml',
      '$videoNameWithoutExt.danmaku.xml',
      '${videoNameWithoutExt}_danmaku.xml',
      '$videoNameWithoutExt.dandan.xml',
      '${videoNameWithoutExt}_dandan.xml',
      '$videoNameWithoutExt.acfun.xml',
      'danmaku.xml',
      '弹幕.xml',
      videoNameWithoutExt, // 无扩展名：与视频同名的裸文件
    ];

/// 从同目录文件名列表中找出第一个命中的同名弹幕文件。
///
/// - [videoNameWithoutExt]：视频文件名（去扩展名）；
/// - [videoFileName]：视频完整文件名（含扩展名）——「无扩展名」候选
///   在视频本身就没有扩展名时会与视频重名，需排除视频自身；
/// - [availableNames]：同目录下全部文件名（仅文件名，不含目录）。
///
/// 返回命中的弹幕文件名；无匹配返回 null。
String? findLocalDanmakuFileName(
  String videoNameWithoutExt,
  String videoFileName,
  Iterable<String> availableNames,
) {
  final available = availableNames.toSet();
  for (final candidate in danmakuCandidateNames(videoNameWithoutExt)) {
    if (candidate == videoFileName) continue; // 排除视频自身
    if (available.contains(candidate)) return candidate;
  }
  return null;
}

/// 弹幕文件选择器过滤（阶段1 只支持 B站 XML 格式）。
///
/// 与字幕选择器的 `isSupportedSubtitleFile` 同款语义：按文件名（大小写
/// 不敏感）过滤，供复用的自建文件选择器面板只显示可导入的弹幕文件。
bool isSupportedDanmakuFile(String filename) {
  final lower = filename.toLowerCase();
  return lower.endsWith('.xml');
}
