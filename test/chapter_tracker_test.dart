import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/services/chapter_tracker.dart';

/// ChapterTracker 测试：用假 [ChapterSource] 注入章节数据与 seek 记录，
/// 验证位置流驱动的章节推进 / 胶囊自动弹出窗口（5 秒倒计时）/
/// 可重复触发 / 跳过与跳转。
/// 假数据源：章节 + 时长固定，seek 目标全部记录
class FakeChapterSource implements ChapterSource {
  FakeChapterSource(this.chapters, this.mediaDuration);

  List<ChapterInfo> chapters;
  Duration mediaDuration;
  final List<Duration> seeks = [];

  @override
  Future<List<ChapterInfo>> loadChapters() async => chapters;

  @override
  Duration get duration => mediaDuration;

  @override
  Future<void> seek(Duration target) async => seeks.add(target);
}

/// 标准番剧章节：OP(60-300) / 正片 / ED(1200-1500)
const chapters = [
  ChapterInfo(title: 'OP', startSeconds: 60),
  ChapterInfo(title: '第 2 话', startSeconds: 300),
  ChapterInfo(title: 'ED', startSeconds: 1200),
];

void main() {
  group('load / clear：章节读取与清空', () {
    test('load 后章节与跳过片段派生完成', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      expect(tracker.chapters, hasLength(3));
      expect(tracker.skipSegments, hasLength(2));
      expect(tracker.skipSegments.first.type, ChapterSkipType.intro);
      tracker.dispose();
    });

    test('无章节媒体：章节与片段均为空', () async {
      final source =
          FakeChapterSource(const [], const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      expect(tracker.chapters, isEmpty);
      expect(tracker.skipSegments, isEmpty);
      expect(tracker.currentChapterTitle, isNull);
      tracker.dispose();
    });

    test('clear 清空全部状态（切集前调用，防旧数据闪现）', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.currentChapterIndex, 0); // OP 区间（60–300s）
      tracker.clear();
      expect(tracker.chapters, isEmpty);
      expect(tracker.skipSegments, isEmpty);
      expect(tracker.currentChapterIndex, isNull);
      expect(tracker.activeSegment, isNull);
      expect(tracker.autoChipVisible, isFalse);
      tracker.dispose();
    });
  });

  group('onPositionChanged：当前章节与跳过片段跟随', () {
    test('位置推进时章节下标变化，回调通知触发', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      var notified = 0;
      tracker.addListener(() => notified++);

      // 10s 在任何章节之前：未定位到章节
      tracker.onPositionChanged(const Duration(seconds: 10));
      expect(tracker.currentChapterIndex, isNull);
      expect(notified, 0);

      // 100s：进入 OP 章节（60s 起）
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.currentChapterIndex, 0);
      expect(notified, 1);

      // 同一章节内位置推进：状态无变化不通知（高频位置流省重建）
      tracker.onPositionChanged(const Duration(seconds: 200));
      expect(tracker.currentChapterIndex, 0);
      expect(notified, 1);

      // 400s：进入「第 2 话」（300s 起）
      tracker.onPositionChanged(const Duration(seconds: 400));
      expect(tracker.currentChapterIndex, 1);
      expect(notified, 2);
      tracker.dispose();
    });

    test('进入片段：activeSegment 就位且自动弹出窗口开启', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.activeSegment?.type, ChapterSkipType.intro);
      expect(tracker.activeSegment?.startSeconds, 60);
      expect(tracker.autoChipVisible, isTrue);
      tracker.dispose();
    });

    test('离开片段：activeSegment 与自动弹出窗口关闭', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.autoChipVisible, isTrue);
      tracker.onPositionChanged(const Duration(seconds: 400));
      expect(tracker.activeSegment, isNull);
      expect(tracker.autoChipVisible, isFalse);
      tracker.dispose();
    });

    test('自动弹出窗口超时后消失（5 秒倒计时）', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(
        source,
        autoChipWindow: const Duration(milliseconds: 50),
      );
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.autoChipVisible, isTrue);
      // 窗口过期后自动消失（片段内仍常驻 activeSegment，仅关闭自动弹出）
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(tracker.autoChipVisible, isFalse);
      expect(tracker.activeSegment, isNotNull);
      tracker.dispose();
    });

    test('回拖出片段再进入：自动弹出可重复触发（工作.md 第 4 点）', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(
        source,
        autoChipWindow: const Duration(milliseconds: 50),
      );
      await tracker.load();
      // 第一次进入 → 弹出 → 窗口过期消失
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.autoChipVisible, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(tracker.autoChipVisible, isFalse);
      // 拖回正片 → 离开片段
      tracker.onPositionChanged(const Duration(seconds: 400));
      expect(tracker.activeSegment, isNull);
      // 再拖回 OP 区间 → 再次自动弹出
      tracker.onPositionChanged(const Duration(seconds: 100));
      expect(tracker.autoChipVisible, isTrue);
      tracker.dispose();
    });
  });

  group('skipActiveSegment / seekToChapter：跳转', () {
    test('点击胶囊：跳到片段结束（EOF 保护）', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 100));
      await tracker.skipActiveSegment();
      expect(source.seeks, [const Duration(seconds: 300)]);
      // 跳过即关闭自动弹出窗口（离开片段由位置流兜底）
      expect(tracker.autoChipVisible, isFalse);
      tracker.dispose();
    });

    test('无所在片段时点击胶囊不动作', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 400));
      await tracker.skipActiveSegment();
      expect(source.seeks, isEmpty);
      tracker.dispose();
    });

    test('跳过片段结束 = 视频末尾：目标留 0.25 秒缓冲', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      tracker.onPositionChanged(const Duration(seconds: 1300));
      await tracker.skipActiveSegment();
      expect(source.seeks, [const Duration(milliseconds: 1499750)]);
      tracker.dispose();
    });

    test('章节列表面板点击：跳到章节起点', () async {
      final source = FakeChapterSource(chapters, const Duration(seconds: 1500));
      final tracker = ChapterTracker(source);
      await tracker.load();
      await tracker.seekToChapter(chapters[1]);
      expect(source.seeks, [const Duration(seconds: 300)]);
      tracker.dispose();
    });
  });
}
