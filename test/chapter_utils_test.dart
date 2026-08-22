import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/utils/chapter_utils.dart';

/// 章节功能纯函数测试（工作.md 章节功能）：
/// 标题分类 / 片段派生 / 当前章节 / 所在片段 / 跳过目标。
void main() {
  group('classifyChapterTitle：章节标题 → 跳过类型', () {
    test('片头关键词：OP / opening / 主题曲 / op1', () {
      expect(classifyChapterTitle('OP'), ChapterSkipType.intro);
      expect(classifyChapterTitle('opening'), ChapterSkipType.intro);
      expect(classifyChapterTitle('主题曲'), ChapterSkipType.intro);
      expect(classifyChapterTitle('op1'), ChapterSkipType.intro);
    });

    test('片尾关键词：ED / ending / エンディング / 片尾曲', () {
      expect(classifyChapterTitle('ED'), ChapterSkipType.outro);
      expect(classifyChapterTitle('Ending 1'), ChapterSkipType.outro);
      expect(classifyChapterTitle('エンディング'), ChapterSkipType.outro);
      expect(classifyChapterTitle('片尾曲'), ChapterSkipType.outro);
    });

    test('正片前段：AVANT → 跳过正片前段（工作.md 明确要求）', () {
      expect(classifyChapterTitle('AVANT'), ChapterSkipType.coldOpen);
      expect(classifyChapterTitle('アバンタイトル'), ChapterSkipType.coldOpen);
      expect(classifyChapterTitle('正片前段'), ChapterSkipType.coldOpen);
    });

    test('下集预告：次回予告 / 预告 / preview', () {
      expect(classifyChapterTitle('次回予告'), ChapterSkipType.preview);
      expect(classifyChapterTitle('下集预告'), ChapterSkipType.preview);
      expect(classifyChapterTitle('preview'), ChapterSkipType.preview);
    });

    test('前情提要 / 制作人员', () {
      expect(classifyChapterTitle('recap'), ChapterSkipType.recap);
      expect(classifyChapterTitle('前情提要'), ChapterSkipType.recap);
      expect(classifyChapterTitle('staff'), ChapterSkipType.credits);
      expect(classifyChapterTitle('制作人员'), ChapterSkipType.credits);
    });

    test('优先级：前情提要 > 片头（标题同时含两词时取前情提要）', () {
      expect(
        classifyChapterTitle('Recap & OP'),
        ChapterSkipType.recap,
      );
    });

    test('op 不误匹配 opening（拉丁词需单词边界）', () {
      // 'opening' 的紧凑形式含 'op' 但 op 长度 < 4 不做包含匹配
      expect(classifyChapterTitle('opening'), ChapterSkipType.intro);
      // 无关键词 → null
      expect(classifyChapterTitle('Chapter 1'), isNull);
      expect(classifyChapterTitle('BONUS'), isNull);
      expect(classifyChapterTitle(''), isNull);
      expect(classifyChapterTitle(null), isNull);
    });
  });

  group('resolveSkipSegments：章节 → 可跳过片段', () {
    const chapters = [
      ChapterInfo(title: 'OP', startSeconds: 60),
      ChapterInfo(title: '第 2 话', startSeconds: 300),
      ChapterInfo(title: 'ED', startSeconds: 1200),
    ];

    test('OP 与 ED 派生片段：end = 下一章节起点或视频时长', () {
      final segments = resolveSkipSegments(chapters, 1500);
      expect(segments, hasLength(2));
      expect(segments[0].type, ChapterSkipType.intro);
      expect(segments[0].startSeconds, 60);
      expect(segments[0].endSeconds, 300);
      expect(segments[1].type, ChapterSkipType.outro);
      expect(segments[1].startSeconds, 1200);
      expect(segments[1].endSeconds, 1500);
    });

    test('非分类章节不产生片段；无章节输入返回空', () {
      expect(resolveSkipSegments([const ChapterInfo(title: 'Chapter 1', startSeconds: 0)], 1500), isEmpty);
      expect(resolveSkipSegments(const [], 1500), isEmpty);
    });

    test('时长无效（≤0）返回空', () {
      expect(resolveSkipSegments(chapters, 0), isEmpty);
      expect(resolveSkipSegments(chapters, -1), isEmpty);
    });

    test('片段时长 < 5 秒排除', () {
      const tight = [
        ChapterInfo(title: 'OP', startSeconds: 60),
        ChapterInfo(title: '正片', startSeconds: 63),
      ];
      expect(resolveSkipSegments(tight, 1500), isEmpty);
    });

    test('INTRO 起点超过视频后半段视为误判排除', () {
      const late = [ChapterInfo(title: 'OP', startSeconds: 1000)];
      expect(resolveSkipSegments(late, 1500), isEmpty);
    });

    test('OUTRO 起点在前 40% 视为误判排除', () {
      const early = [ChapterInfo(title: 'ED', startSeconds: 100)];
      expect(resolveSkipSegments(early, 1500), isEmpty);
    });

    test('片段结束时间钳制到视频时长内', () {
      // OP 起点在前半段（30/100 < 0.5），否则会被 INTRO 误判规则排除
      const overflow = [ChapterInfo(title: 'OP', startSeconds: 30)];
      final segments = resolveSkipSegments(overflow, 100);
      expect(segments.single.endSeconds, 100);
    });
  });

  group('currentChapterIndex：当前位置所属章节', () {
    const chapters = [
      ChapterInfo(title: 'A', startSeconds: 0),
      ChapterInfo(title: 'B', startSeconds: 60),
      ChapterInfo(title: 'C', startSeconds: 300),
    ];

    test('按区间定位（含起点、不含下一章起点）', () {
      expect(currentChapterIndex(chapters, 0), 0);
      expect(currentChapterIndex(chapters, 59.9), 0);
      expect(currentChapterIndex(chapters, 60), 1);
      expect(currentChapterIndex(chapters, 100), 1);
      expect(currentChapterIndex(chapters, 1000), 2);
    });

    test('第一章之前 / 空列表 → null', () {
      expect(currentChapterIndex(chapters, -1), isNull);
      expect(currentChapterIndex(const [], 10), isNull);
    });
  });

  group('activeSegmentAt：当前位置所在跳过片段', () {
    const segments = [
      SkipSegment(
        type: ChapterSkipType.intro,
        startSeconds: 60,
        endSeconds: 300,
      ),
    ];

    test('片段区间内返回片段', () {
      expect(activeSegmentAt(segments, 60), segments[0]);
      expect(activeSegmentAt(segments, 100), segments[0]);
      expect(activeSegmentAt(segments, 299), segments[0]);
    });

    test('距片段结束不足 1 秒不返回（跳过已无意义）', () {
      expect(activeSegmentAt(segments, 299.5), isNull);
      expect(activeSegmentAt(segments, 300), isNull);
    });

    test('区间外不返回', () {
      expect(activeSegmentAt(segments, 59), isNull);
      expect(activeSegmentAt(segments, 1000), isNull);
      expect(activeSegmentAt(const [], 100), isNull);
    });

    test('无效片段（时长 ≤ 1 秒）即使位置在区间内也不返回', () {
      const invalid = [
        SkipSegment(
          type: ChapterSkipType.preview,
          startSeconds: 100,
          endSeconds: 100.5,
        ),
      ];
      expect(activeSegmentAt(invalid, 100.2), isNull);
    });
  });

  group('skipSeekTarget：跳过目标（EOF 保护）', () {
    const seg = SkipSegment(
      type: ChapterSkipType.intro,
      startSeconds: 60,
      endSeconds: 300,
    );

    test('未到视频末尾：直接跳片段结束', () {
      expect(skipSeekTarget(seg, 1500), 300);
    });

    test('片段结束 = 视频末尾：留 0.25 秒缓冲', () {
      const toEof = SkipSegment(
        type: ChapterSkipType.outro,
        startSeconds: 1200,
        endSeconds: 1500,
      );
      expect(skipSeekTarget(toEof, 1500), 1499.75);
    });

    test('片段几乎覆盖全片且缓冲点仍在片内：跳中点', () {
      const full = SkipSegment(
        type: ChapterSkipType.intro,
        startSeconds: 99.9,
        endSeconds: 100,
      );
      expect(skipSeekTarget(full, 100), 99.95);
    });

    test('时长无效：直接返回片段结束', () {
      expect(skipSeekTarget(seg, 0), 300);
    });
  });
}
