import 'package:flutter/material.dart';

/// 播放器右侧面板中的选项胶囊（倍速预设 / 超分模式共用）。
///
/// 点击生效并高亮：选中态以主题色填充、白字加粗；未选中为半透明白底。
/// 倍速面板与超分面板共用此组件，保证两处交互与视觉完全一致。
class PlayerOptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 内边距（自定义倍速预设胶囊会传入更宽的右内边距，给删除角标留位）
  final EdgeInsets padding;

  /// 文字对齐（超分面板三行等宽胶囊用居中；倍速面板默认左对齐）
  final TextAlign textAlign;

  /// 文本最大行数（默认 null = 不限制；传 1 时文本不换行、超出省略号，
  /// 用于等宽两行布局保证胶囊高度一致）
  final int? maxLines;

  const PlayerOptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.textAlign = TextAlign.left,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: padding,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? scheme.onPrimary : Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
