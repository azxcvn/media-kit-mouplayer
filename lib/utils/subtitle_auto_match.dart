/// 同名字幕自动匹配（对齐小喵 player `VideoPlayerActivity+Subtitle.kt`）。
///
/// 纯函数（无 Flutter 依赖）：给定视频文件名（不含扩展名）与同目录下候选文件
/// 名列表，按小喵 player 的排序算法选出「最佳匹配」字幕：
/// 1. 扩展名优先级 ass > srt > ssa > vtt > sub > sbv > json；
/// 2. 与视频名完全同名（不含后缀）优先；
/// 3. 语言后缀优先：简体系统优先 `sc`/`chs`/`简`/`zh-cn`，
///    繁体系统优先 `tc`/`cht`/`繁`/`zh-tw`；
/// 4. 名字（去扩展名）越短越优先；
/// 5. 全名小写字母序兜底。
///
/// 系统语言以 Android 风格 locale 串传入（如 `zh_cn`/`zh_tw`/`zh_hk`），
/// 由调用方从 `PlatformDispatcher` 取。
library;

/// 字幕优先级（对齐小喵 player 的 `SUBTITLE_PRIORITY`）。
const List<String> kSubtitleAutoPriority = [
  'ass', 'srt', 'ssa', 'vtt', 'sub', 'sbv', 'json',
];

/// 取扩展名（不含点；无扩展名返回空串，对齐 Kotlin `substringAfterLast('.',"")`）。
String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1);
}

/// 取去扩展名的主名（对齐 Kotlin `substringBeforeLast('.')`）。
String _base(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

/// 去掉前导前缀（对齐 Kotlin `removePrefix`：仅当前缀匹配时移除，否则原样返回）。
String _removePrefix(String s, String prefix) =>
    s.startsWith(prefix) ? s.substring(prefix.length) : s;

/// 是否候选同名字幕：文件名（小写）以视频名（小写）开头，且扩展名在优先级列表内。
bool isSameBaseSubtitle(String fileName, String videoNameWithoutExt) {
  final name = fileName.toLowerCase();
  final videoName = videoNameWithoutExt.toLowerCase();
  if (!name.startsWith(videoName)) return false;
  return kSubtitleAutoPriority.contains(_ext(fileName).toLowerCase());
}

/// 语言后缀优先级（对齐小喵 `langPriority`）。
///
/// [afterVideoName] 为「去扩展名 + 去掉视频名前缀」后的小写后缀（如 `.sc`/`.tc`）；
/// 简体系统命中 sc/chs/简/zh-cn、繁体系统命中 tc/cht/繁/zh-tw 返回 0（优先），
/// 否则返回 1。
int langPriority(String afterVideoName, {required bool isSC, required bool isTC}) {
  if (isSC &&
      (afterVideoName.contains('sc') ||
          afterVideoName.contains('chs') ||
          afterVideoName.contains('简') ||
          afterVideoName.contains('zh-cn'))) {
    return 0;
  }
  if (isTC &&
      (afterVideoName.contains('tc') ||
          afterVideoName.contains('cht') ||
          afterVideoName.contains('繁') ||
          afterVideoName.contains('zh-tw'))) {
    return 0;
  }
  return 1;
}

/// 两个候选文件名的比较器（对齐小喵 `subtitleFileNameComparator`，String 版本）。
int compareSubtitleFileNames(
  String a,
  String b,
  String videoNameWithoutExt, {
  required bool isSC,
  required bool isTC,
}) {
  // 1. 扩展名优先级
  final aExt = kSubtitleAutoPriority.indexOf(_ext(a).toLowerCase());
  final bExt = kSubtitleAutoPriority.indexOf(_ext(b).toLowerCase());
  final aP = aExt == -1 ? 999 : aExt;
  final bP = bExt == -1 ? 999 : bExt;
  if (aP != bP) return aP - bP;

  // 2. 完全同名优先
  final aExact =
      _base(a).toLowerCase() == videoNameWithoutExt.toLowerCase() ? 0 : 1;
  final bExact =
      _base(b).toLowerCase() == videoNameWithoutExt.toLowerCase() ? 0 : 1;
  if (aExact != bExact) return aExact - bExact;

  // 3. 语言后缀
  final aAfter =
      _removePrefix(_base(a).toLowerCase(), videoNameWithoutExt.toLowerCase());
  final bAfter =
      _removePrefix(_base(b).toLowerCase(), videoNameWithoutExt.toLowerCase());
  final aLang = langPriority(aAfter, isSC: isSC, isTC: isTC);
  final bLang = langPriority(bAfter, isSC: isSC, isTC: isTC);
  if (aLang != bLang) return aLang - bLang;

  // 4. 名字（去扩展名）长度
  final aLen = _base(a).length;
  final bLen = _base(b).length;
  if (aLen != bLen) return aLen - bLen;

  // 5. 全名小写字母序
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// 从候选文件名列表里选出最佳同名字幕（对齐小喵 `findBestSubtitleFileName`）。
///
/// [availableFileNames] 传文件**名**（不含目录）；[systemLanguage] 为小写的
/// Android 风格 locale 串（如 `zh_cn`/`zh_tw`/`zh_hk`/`en_us`）。无匹配返回 null。
String? findBestSubtitleFileName(
  String videoNameWithoutExt,
  List<String> availableFileNames, {
  String systemLanguage = 'zh_cn',
}) {
  final isSC = systemLanguage.contains('zh_cn');
  final isTC =
      systemLanguage.contains('zh_tw') || systemLanguage.contains('zh_hk');
  final matching = availableFileNames
      .where((f) => isSameBaseSubtitle(f, videoNameWithoutExt))
      .toList();
  if (matching.isEmpty) return null;
  matching.sort(
    (a, b) => compareSubtitleFileNames(
      a,
      b,
      videoNameWithoutExt,
      isSC: isSC,
      isTC: isTC,
    ),
  );
  return matching.first;
}
