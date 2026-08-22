/// 章节功能纯函数算法（无 media_kit / Flutter UI 依赖，可单测）。
///
/// 算法思路对齐参考项目（小喵 player 的 chapterTitleToType /
/// refreshChapterDerivedSegments / updateSkipChipState，mpvRx 的
/// SkipMarkerResolver），输出可跳过片段、当前章节等派生数据。
library;

import 'package:moumou/models/chapter_info.dart';

/// 内置关键词（多语言，借鉴参考项目）：
/// 片头（OP）/ 片尾（ED）/ 前情提要 / 制作人员 / 正片前段 / 下集预告
const List<String> chapterIntroKeywords = [
  'intro', 'opening', 'op', 'op1', 'op2', 'op3',
  'オープニング', '主題歌', '主题曲', '片头', '开幕', '片头曲', '序章',
  'prologue', 'avance', 'a partire', '开场', '头曲',
];

const List<String> chapterOutroKeywords = [
  'outro', 'ending', 'ed', 'ed1', 'ed2', 'ed3',
  'エンディング', '片尾', '结尾', '片尾曲', '尾曲', '闭幕',
  'epilogue', 'finale', 'credits', 'closing', 'fin', 'fine',
];

const List<String> chapterRecapKeywords = [
  'recap', 'summary', '振り返り', '前回', '回顾', '复习', '总集',
  'résumé', 'riepilogo', 'resumen', '前情提要', '上集回顾', '前回まで', 'これまで',
];

const List<String> chapterCreditsKeywords = [
  'credits', 'end credits', 'staff', 'cast',
  '制作', 'スタッフ', '出演', '声の出演', 'creditless', 'クレジット',
];

/// 片头前段（avant / アバンタイトル）：正片开始、OP 之前的一小段正片内容
const List<String> chapterColdOpenKeywords = [
  'avant', 'アバン', 'アバンタイトル', '冷开场', '正片前段', '片头前段',
];

const List<String> chapterPreviewKeywords = [
  'preview', 'next episode', '次回予告', '予告', '预告', '下集',
  '次回', '次巻', '次回预告', '先行', 'trailer',
];

/// 片段最短有效时长（秒）：短于该值的派生片段直接丢弃
const double minSkipSegmentSeconds = 5.0;

/// 章节标题 → 跳过片段类型。
///
/// 匹配规则（参考小喵 player）：
/// - 拉丁词：`(?:^|\s)kw(?:\s|$)` 单词边界匹配，或长度 ≥ 4 时紧凑包含匹配
///   （如 "op" 只匹配独立单词，避免 "opening" 被 "op" 误匹配冲突）；
/// - 非拉丁（中文/日文/带重音）：去空白与标点后子串包含匹配。
///
/// 优先级（参考 mpvRx）：前情提要 > 正片前段 > 制作人员 > 下集预告 >
/// 片尾（且非片头）> 片头；无法识别返回 null。
ChapterSkipType? classifyChapterTitle(String? title) {
  if (title == null || title.trim().isEmpty) return null;
  final lowered = title.trim().toLowerCase();
  final normalizedLatin =
      lowered.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final compactLatin = normalizedLatin.replaceAll(' ', '');
  final compactRaw = lowered.replaceAll(RegExp(r'[\s\p{Punct}・_]+'), '');

  bool hasKeyword(List<String> keywords) {
    for (final raw in keywords) {
      final kw = raw.toLowerCase();
      if (kw.isEmpty) continue;
      final matched = RegExp(r'[a-z0-9]+').hasMatch(kw)
          ? normalizedLatin.contains(RegExp('(?:^|\\s)${RegExp.escape(kw)}(?:\\s|\$)')) ||
              (kw.length >= 4 && compactLatin.contains(kw))
          : compactRaw.contains(kw.replaceAll(' ', ''));
      if (matched) return true;
    }
    return false;
  }

  final hasIntro = hasKeyword(chapterIntroKeywords);
  final hasOutro = hasKeyword(chapterOutroKeywords);
  return switch ((hasKeyword(chapterRecapKeywords), hasKeyword(chapterColdOpenKeywords), hasKeyword(chapterCreditsKeywords), hasKeyword(chapterPreviewKeywords), hasOutro, hasIntro)) {
    (true, _, _, _, _, _) => ChapterSkipType.recap,
    (_, true, _, _, false, false) => ChapterSkipType.coldOpen,
    (_, _, true, _, false, false) => ChapterSkipType.credits,
    (_, _, _, true, false, false) => ChapterSkipType.preview,
    (_, _, _, _, true, false) => ChapterSkipType.outro,
    (_, _, _, _, _, true) => ChapterSkipType.intro,
    _ => null,
  };
}

/// 由章节列表派生可跳过片段（参考小喵 refreshChapterDerivedSegments）：
/// - 片段 end = 下一章节起点或视频时长（钳制到时长内）；
/// - 时长 < [minSkipSegmentSeconds] 的片段丢弃；
/// - INTRO 起点超过视频后半段（fraction > 0.5）、OUTRO 起点在前 40% 的
///   视为误判丢弃（正常番剧 OP 靠前、ED 靠后）；
/// - 类型相同且起止（取整后）重复的片段去重。
List<SkipSegment> resolveSkipSegments(
  List<ChapterInfo> chapters,
  double durationSeconds,
) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) return const [];
  final result = <SkipSegment>[];
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (!chapter.startSeconds.isFinite || chapter.startSeconds < 0) continue;
    final type = classifyChapterTitle(chapter.title);
    if (type == null) continue;
    final end = i + 1 < chapters.length
        ? chapters[i + 1].startSeconds
        : durationSeconds;
    final normalizedEnd = end.clamp(0.0, durationSeconds);
    if (normalizedEnd - chapter.startSeconds < minSkipSegmentSeconds) {
      continue;
    }
    final fraction = chapter.startSeconds / durationSeconds;
    switch (type) {
      case ChapterSkipType.intro:
        if (fraction > 0.5) continue;
      case ChapterSkipType.outro:
        if (fraction < 0.4) continue;
      case ChapterSkipType.recap:
      case ChapterSkipType.credits:
      case ChapterSkipType.coldOpen:
      case ChapterSkipType.preview:
        break;
    }
    final segment = SkipSegment(
      type: type,
      startSeconds: chapter.startSeconds,
      endSeconds: normalizedEnd,
    );
    final duplicate = result.any((e) =>
        e.type == segment.type &&
        e.startSeconds.round() == segment.startSeconds.round() &&
        e.endSeconds.round() == segment.endSeconds.round());
    if (!duplicate) result.add(segment);
  }
  return result;
}

/// 当前播放位置所属章节下标（从后往前找最后一个 startSeconds <= 位置；
/// 位置在第一章之前返回 null）。
int? currentChapterIndex(List<ChapterInfo> chapters, double positionSeconds) {
  if (chapters.isEmpty) return null;
  for (var i = chapters.length - 1; i >= 0; i--) {
    if (chapters[i].startSeconds <= positionSeconds) return i;
  }
  return null;
}

/// 当前位置所在的可跳过片段（参考小喵 updateSkipChipState）：
/// - 片段必须有效，且位置在 [startSeconds, endSeconds] 区间内；
/// - 距片段结束不足 1 秒时不返回（跳过已无意义）。
SkipSegment? activeSegmentAt(
  List<SkipSegment> segments,
  double positionSeconds,
) {
  for (final seg in segments) {
    if (seg.isValid &&
        positionSeconds >= seg.startSeconds &&
        positionSeconds <= seg.endSeconds &&
        seg.endSeconds - positionSeconds >= 1.0) {
      return seg;
    }
  }
  return null;
}

/// 片段末尾 1 秒内不再视为可跳过
const double skipSegmentTailGuard = 1.0;

/// 跳过目标时间（秒）：片段 end 未到视频末尾时直接跳 end；
/// 跳到末尾时留 [eofSeekGuard] 秒缓冲，避免触发 EOF 连播/退出。
double skipSeekTarget(SkipSegment segment, double durationSeconds) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    return segment.endSeconds;
  }
  final end = segment.endSeconds.clamp(0.0, durationSeconds);
  if (end < durationSeconds) return end;
  const guard = 0.25;
  final guarded = durationSeconds - guard;
  if (guarded > segment.startSeconds) return guarded;
  // 片段几乎覆盖整个视频：跳到中点（仍留在原片段内的最远安全点）
  return segment.startSeconds + (durationSeconds - segment.startSeconds) / 2.0;
}
