import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/services/chapter_tracker.dart';
import 'package:moumou/utils/formatters.dart';

/// 章节列表面板内容（横屏经 [showPlayerPanel] 右侧滑入，竖屏经
/// [showPlayerBottomPanel] 底部弹出，标题「章节」）。
///
/// 样式参考小喵 player 的 ChapterDrawer：
/// - 竖向列表可滚动，每项 = 章节标题（占满）+ 右侧起始时间文本；
/// - 当前章节以主题色高亮（浅色底 + 主题色文字加粗）；
/// - 面板内 ListenableBuilder 监听 [ChapterTracker]：播放中章节推进时
///   高亮实时跟随（与播放列表面板同款「面板局部状态」思路）；
/// - 点击列表项 → [onSelect] 回调（播放页 seek），随后面板自行关闭。
class PlayerChapterPanel extends StatelessWidget {
  /// 章节状态源（当前章节下标 + 章节列表，实时跟随）
  final ChapterTracker tracker;

  /// 点击章节回调（由播放页执行跳转）
  final ValueChanged<ChapterInfo> onSelect;

  const PlayerChapterPanel({
    super.key,
    required this.tracker,
    required this.onSelect,
  });

  void _handleSelect(BuildContext context, ChapterInfo chapter) {
    onSelect(chapter);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final chapters = tracker.chapters;
        if (chapters.isEmpty) {
          return const Center(
            child: Text(
              '当前视频无章节信息',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          );
        }
        final currentIndex = tracker.currentChapterIndex;
        final scheme = Theme.of(context).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: chapters.length,
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            final isCurrent = index == currentIndex;
            return InkWell(
              onTap: () => _handleSelect(context, chapter),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: isCurrent
                    ? BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                      )
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? scheme.primary : Colors.white,
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDuration((chapter.startSeconds * 1000).round()),
                      style: TextStyle(
                        color: isCurrent
                            ? scheme.primary.withValues(alpha: 0.8)
                            : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
