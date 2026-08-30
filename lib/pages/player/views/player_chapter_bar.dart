import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_pressable.dart';

/// 当前章节名称行：位于进度条上方，点击呼出章节列表。
///
/// 样式参考小喵 player 的章节名称行（12sp 白 0.8 + ❯ 提示可点），
/// 点击区域与名称自适应（Row 按内容收缩，仅包住文字与箭头）。
class PlayerChapterNameRow extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  /// 外边距（默认竖屏底栏样式）；横屏底栏传更大的 bottom 让章节名行
  /// 跟随进度条下移（保持与轨道的间距不变）。
  final EdgeInsetsGeometry padding;

  const PlayerChapterNameRow({
    super.key,
    required this.name,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(kPlayerLeftInset, 8, 20, 2),
  });

  @override
  Widget build(BuildContext context) {
    return PlayerPressable(
      onTap: onTap,
      child: Padding(
        // 左缘与进度条开端对齐，右缘与底栏一致
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

/// 跳过胶囊（OP/ED/预告等）：底色 = 片段类型专属色，白字 + 跳过图标。
///
/// 样式参考 mpvRx（类型色低亮度底 + 高亮度描边）与小喵 player
/// （类型色高透明度底 + 全圆角）的折中：类型色 0.92 底 + 轻微阴影，
/// 保证在视频画面上清晰可辨且与类型色一致。
class ChapterSkipChip extends StatelessWidget {
  final ChapterSkipType type;
  final VoidCallback onTap;

  const ChapterSkipChip({super.key, required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PlayerPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.skip_next_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              type.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
