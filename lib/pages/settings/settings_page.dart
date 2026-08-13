import 'package:flutter/material.dart';
import 'package:moumou/theme/theme_controller.dart';

/// 设置页：外观模式 + 主题色
class SettingsPage extends StatelessWidget {
  final ThemeController controller;

  const SettingsPage({super.key, required this.controller});

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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _sectionHeader(context, '外观模式'),
              ...AppThemeMode.values.map((mode) {
                final selected = controller.mode == mode;
                return ListTile(
                  leading: Icon(
                    _modeIcon(mode),
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  title: Text(mode.label),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () => controller.setMode(mode),
                );
              }),
              const Divider(),
              _sectionHeader(context, '主题色'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: ThemeController.presetColors.map((color) {
                    final selected = controller.seedColor == color;
                    return GestureDetector(
                      onTap: () => controller.setSeedColor(color),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: scheme.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 22)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              _sectionHeader(context, '调色板风格'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      ThemeController.variantLabels.entries.map((entry) {
                    final selected = controller.variant == entry.key;
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: selected,
                      onSelected: (_) => controller.setVariant(entry.key),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
