import 'package:flutter/material.dart';
import 'package:moumou/theme/theme_controller.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 外观设置子页：外观模式 / 主题色 / 调色板风格
///
/// 主题色：纯代表色块 + 名称，固定行列网格；调色板风格：固定网格按钮。
/// 两者均无预览、无布局跳动（选中态用边框 + 角标，格子尺寸恒定）。
class AppearancePage extends StatelessWidget {
  final ThemeController controller;

  const AppearancePage({super.key, required this.controller});

  IconData _modeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return Icons.brightness_auto;
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.amoled:
        return Icons.nights_stay;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          // 底部安全区已由全局 SafeArea 处理
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              // 外观模式
              const SettingsGroupTitle(title: '外观模式'),
              SettingsCard(
                child: Column(
                  children: [
                    for (final mode in AppThemeMode.values)
                      SettingsRadioTile(
                        icon: _modeIcon(mode),
                        title: mode.label,
                        selected: controller.mode == mode,
                        onTap: () => controller.setMode(mode),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 主题色：纯代表色块 + 名称（固定 4 列网格，卡片包裹）
              const SettingsGroupTitle(title: '主题色'),
              SettingsCard(
                padding: const EdgeInsets.all(12),
                child: _ColorGrid(
                  crossAxisCount: 4,
                  childAspectRatio: 1.0,
                  itemCount: ThemeController.presetColors.length,
                  itemBuilder: (context, index) {
                    final preset = ThemeController.presetColors[index];
                    final selected = controller.seedColor == preset.color;
                    return _SelectionTile(
                      label: preset.label,
                      selected: selected,
                      onTap: () => controller.setSeedColor(preset.color),
                      child: Container(
                        decoration: BoxDecoration(
                          color: preset.color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              // 调色板风格：固定 4 列网格按钮（卡片包裹）
              const SettingsGroupTitle(title: '调色板风格'),
              SettingsCard(
                padding: const EdgeInsets.all(12),
                child: _ColorGrid(
                  crossAxisCount: 4,
                  childAspectRatio: 1.8,
                  itemCount: ThemeController.variantLabels.length,
                  itemBuilder: (context, index) {
                    final entry = ThemeController.variantLabels.entries
                        .elementAt(index);
                    final selected = controller.variant == entry.key;
                    return _SelectionTile(
                      selected: selected,
                      onTap: () => controller.setVariant(entry.key),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                          child: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 固定列数的紧凑网格（shrinkWrap + 不可滚动，跟随外层 ListView）
class _ColorGrid extends StatelessWidget {
  final int crossAxisCount;
  final double childAspectRatio;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _ColorGrid({
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// 网格中的单个可选项：内容区 + 可选名称 + 选中高亮。
///
/// 选中效果符合当前主题（primaryContainer 背景 + primary 描边 + 角标），
/// 切换选中态时背景/描边/文字颜色平滑过渡，角标弹性弹出，格子尺寸恒定。
class _SelectionTile extends StatelessWidget {
  final Widget child;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.child,
    required this.selected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // 内部留白随边框宽度微调，保证内容位置稳定
                  child: Padding(
                    padding: EdgeInsets.all(selected ? 3 : 4),
                    child: child,
                  ),
                ),
                // 选中角标：弹性弹出 + 淡入
                if (selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.elasticOut,
                      builder: (context, value, _) {
                        return Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: value,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surfaceContainerLow,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.check,
                                size: 10,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 5),
            // 固定单行标签，颜色/字重随选中态平滑过渡
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 12,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
