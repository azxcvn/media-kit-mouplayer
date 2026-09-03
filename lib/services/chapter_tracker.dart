import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/utils/chapter_utils.dart' as chapter_utils;

/// 章节数据来源抽象（测试注入假实现；生产实现见 [MpvChapterSource]）。
abstract class ChapterSource {
  /// 从播放器读取当前媒体的章节列表
  Future<List<ChapterInfo>> loadChapters();

  /// 当前媒体时长
  Duration get duration;

  /// 跳转到目标时间
  Future<void> seek(Duration target);
}

/// 基于 media_kit 的 mpv 子属性读取章节（参考小喵 player 的
/// `chapter-list/count` + `chapter-list/$i/title` + `chapter-list/$i/time`）。
class MpvChapterSource implements ChapterSource {
  MpvChapterSource(this._player);

  final Player _player;

  @override
  Future<List<ChapterInfo>> loadChapters() async {
    final native = _player.platform;
    if (native is! NativePlayer) return const [];
    final countStr = await native.getProperty('chapter-list/count');
    final count = int.tryParse(countStr) ?? 0;
    if (count <= 0) return const [];
    final result = <ChapterInfo>[];
    for (var i = 0; i < count; i++) {
      final title = await native.getProperty('chapter-list/$i/title');
      final timeStr = await native.getProperty('chapter-list/$i/time');
      final start = double.tryParse(timeStr);
      if (start == null || !start.isFinite) continue;
      result.add(ChapterInfo(title: title, startSeconds: start));
    }
    return result;
  }

  @override
  Duration get duration => _player.state.duration;

  @override
  Future<void> seek(Duration target) => _player.seek(target);
}

/// 章节状态跟踪器：由播放位置流驱动，维护「当前章节 / 所在跳过片段 /
/// 跳过胶囊自动弹出窗口」三态，横竖屏播放页共享同一实例。
///
/// - 位置流每次更新调用 [onPositionChanged]（高频、纯计算，只在状态
///   变化时 notifyListeners，避免无效重建）；
/// - 进入跳过片段时自动弹出胶囊并启动 [autoChipWindow] 倒计时，
///   超时自动消失；回拖出片段再进入可重复触发（工作.md 第 4 点）；
/// - 胶囊常驻显示由 UI 层组合判断：`autoChipVisible || 控制层可见`。
class ChapterTracker extends ChangeNotifier {
  ChapterTracker(this._source, {this.autoChipWindow = const Duration(seconds: 5)});

  final ChapterSource _source;

  /// 自动弹出窗口时长（工作.md 第 4 点：弹出后 5 秒倒计时自动消失；
  /// 测试可注入更短窗口）
  final Duration autoChipWindow;

  List<ChapterInfo> _chapters = const [];
  List<SkipSegment> _skipSegments = const [];
  int? _currentChapterIndex;
  SkipSegment? _activeSegment;
  bool _autoChipVisible = false;
  Timer? _chipTimer;

  /// 当前媒体的章节列表（空 = 无章节）
  List<ChapterInfo> get chapters => _chapters;

  /// 由章节派生出的可跳过片段（OP/ED/预告等）
  List<SkipSegment> get skipSegments => _skipSegments;

  /// 当前播放位置所属章节下标（第一章之前为 null）
  int? get currentChapterIndex => _currentChapterIndex;

  /// 当前播放位置所在的可跳过片段（不在片段内为 null）
  SkipSegment? get activeSegment => _activeSegment;

  /// 是否处于自动弹出窗口（进入片段后 5 秒内）
  bool get autoChipVisible => _autoChipVisible;

  /// 当前章节标题（无章节或未定位到章节时为 null）
  String? get currentChapterTitle =>
      _currentChapterIndex == null ? null : _chapters[_currentChapterIndex!].title;

  /// 打开媒体 / 切集后调用：读取章节并派生跳过片段。
  ///
  /// 时序说明：open 完成后调用（此时时长已就绪），失败或空章节
  /// 静默清空（非章节媒体不展示任何标记）。
  Future<void> load() async {
    _chipTimer?.cancel();
    _autoChipVisible = false;
    _currentChapterIndex = null;
    _activeSegment = null;
    List<ChapterInfo> chapters;
    try {
      chapters = await _source.loadChapters();
    } catch (_) {
      chapters = const [];
    }
    _chapters = chapters;
    _skipSegments = chapters.isEmpty
        ? const []
        : chapter_utils.resolveSkipSegments(
            chapters,
            _source.duration.inMilliseconds / 1000.0,
          );
    notifyListeners();
  }

  /// 切集前调用：立即清空状态（不等 load 完成，避免旧媒体数据闪现）
  void clear() {
    _chipTimer?.cancel();
    _autoChipVisible = false;
    _chapters = const [];
    _skipSegments = const [];
    _currentChapterIndex = null;
    _activeSegment = null;
    notifyListeners();
  }

  /// 直接设置外部章节与跳过片段（B 站 playurl 的 `clip_info_list` 等已有
  /// 精确起止时间的来源，不走章节标题关键词派生）。
  void setExternalChapters(
    List<ChapterInfo> chapters,
    List<SkipSegment> segments,
  ) {
    _chipTimer?.cancel();
    _autoChipVisible = false;
    _chapters = List.of(chapters);
    _skipSegments = List.of(segments);
    _currentChapterIndex = null;
    _activeSegment = null;
    notifyListeners();
  }

  /// 播放位置流驱动：更新当前章节与所在跳过片段。
  ///
  /// 进入片段（从无到有）时启动自动弹出窗口；离开片段时立即关闭窗口。
  /// 状态无变化时不通知（高频位置流下的省重建优化）。
  void onPositionChanged(Duration position) {
    if (_chapters.isEmpty) return;
    final pos = position.inMilliseconds / 1000.0;
    var changed = false;
    final idx = chapter_utils.currentChapterIndex(_chapters, pos);
    if (idx != _currentChapterIndex) {
      _currentChapterIndex = idx;
      changed = true;
    }
    final segment = chapter_utils.activeSegmentAt(_skipSegments, pos);
    if (segment != _activeSegment) {
      _activeSegment = segment;
      if (segment != null) {
        // 进入片段：自动弹出胶囊，窗口结束后消失（可重复触发）
        _autoChipVisible = true;
        _chipTimer?.cancel();
        _chipTimer = Timer(autoChipWindow, () {
          _autoChipVisible = false;
          notifyListeners();
        });
      } else {
        _autoChipVisible = false;
        _chipTimer?.cancel();
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 点击胶囊：跳到当前片段结束（EOF 保护见 [skipSeekTarget]）。
  Future<void> skipActiveSegment() async {
    final segment = _activeSegment;
    if (segment == null) return;
    _chipTimer?.cancel();
    _autoChipVisible = false;
    final dur = _source.duration.inMilliseconds / 1000.0;
    await _source.seek(
      Duration(milliseconds: (chapter_utils.skipSeekTarget(segment, dur) * 1000).round()),
    );
  }

  /// 跳转到指定章节起点（章节列表面板点击）。
  Future<void> seekToChapter(ChapterInfo chapter) async {
    await _source.seek(
      Duration(milliseconds: (chapter.startSeconds * 1000).round()),
    );
  }

  @override
  void dispose() {
    _chipTimer?.cancel();
    super.dispose();
  }
}
