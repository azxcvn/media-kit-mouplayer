import 'package:flutter/material.dart';

/// 底部导航项
class CapsuleNavItem {
  final IconData icon;
  final String label;
  final Widget page;

  const CapsuleNavItem({
    required this.icon,
    required this.label,
    required this.page,
  });
}

/// Telegram 风格胶囊式底部导航
class CapsuleNavBar extends StatelessWidget {
  final List<CapsuleNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const CapsuleNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    // 用 viewPadding 规避系统导航键（手势/三键都兼容）
    return Padding(
      padding: EdgeInsets.fromLTRB(
        viewPadding.left,
        0,
        viewPadding.right,
        8 + viewPadding.bottom,
      ),
      child: SizedBox(
        height: 64,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 172,
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: scheme.surfaceContainer,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / items.length;
                final indicatorWidth = itemWidth * 0.82;
                final indicatorHeight = constraints.maxHeight;

                return Stack(
                  children: [
                    // 滑动 + 涟漪扩散指示器
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * itemWidth +
                          (itemWidth - indicatorWidth) / 2,
                      top: 0,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(selectedIndex),
                        tween: Tween(begin: 0.55, end: 1.0),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) {
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: Container(
                          width: indicatorWidth,
                          height: indicatorHeight,
                          decoration: ShapeDecoration(
                            color: scheme.primaryContainer,
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 内容层（图标 + 文字）
                    Row(
                      children: List.generate(items.length, (index) {
                        return Expanded(
                          child: _CapsuleItem(
                            icon: items[index].icon,
                            label: items[index].label,
                            selected: index == selectedIndex,
                            onTap: () => onSelected(index),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CapsuleItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
