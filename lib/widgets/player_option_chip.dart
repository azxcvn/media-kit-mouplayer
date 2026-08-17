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

  const PlayerOptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.textAlign = TextAlign.left,
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
