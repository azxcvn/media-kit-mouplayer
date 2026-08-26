import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/services/chapter_tracker.dart';
import 'package:moumou/utils/formatters.dart';

/// 章节列表面板内容（横屏经 [showPlayerPanel] 右侧滑入，竖屏经
/// [showPlayerBottomPanel] 底部弹出，标题「章节」）。
///
/// - 竖向列表可滚动，每项 = 序号徽章 + 章节标题（占满）+ 右侧起始时间；
/// - 当前章节以主题色高亮（主题色底 + 描边 + 主题色文字加粗 + 播放指示）；
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: chapters.length + 1,
          itemBuilder: (context, index) {
            // 顶部：章节总数
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                child: Text(
                  '共 ${chapters.length} 章',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              );
            }
            final i = index - 1;
            final chapter = chapters[i];
            final isCurrent = i == currentIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _handleSelect(context, chapter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? scheme.primary.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: isCurrent
                        ? Border.all(
                            color: scheme.primary.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // 序号徽章
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? scheme.primary
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${i + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                            color: isCurrent
                                ? scheme.onPrimary
                                : Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                      // 当前章节显示播放指示，否则显示起始时间
                      if (isCurrent)
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: scheme.primary,
                        )
                      else
                        Text(
                          formatDuration(
                            (chapter.startSeconds * 1000).round(),
                          ),
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
