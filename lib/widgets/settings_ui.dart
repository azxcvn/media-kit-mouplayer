import 'package:flutter/material.dart';

/// 现代化设置界面的公共组件：分组标题 + 圆角卡片 + 设置项行。
/// 供设置主页面、外观子页及后续新增的设置页复用。

/// Kazumi 风格滑块主题：2024 新式滑杆外观（缺口轨道 + 小柄拇指），
/// 无拖拽气泡（数值由外部读数展示）。设置页档位滑杆与播放器倍速面板共用。
SliderThemeData kazumiSliderTheme(ColorScheme scheme) => SliderThemeData(
      // 显式选择 2024 新式滑杆外观（Kazumi 同款）。year2023 是兼容开关，
      // 默认仍为旧式大圆钮，必须显式关闭才生效。
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.secondaryContainer,
      thumbColor: scheme.primary,
      showValueIndicator: ShowValueIndicator.never,
    );

/// 密集档位滑杆（divisions 很大）的刻度点形状。
///
/// Flutter 的 Slider 在刻度过密时（间距 < 3 × 刻度宽）会整条跳过绘制
/// 刻度（见 slider.dart 的密度检查），导致长按倍速这类 50 档滑杆看起来
/// 没有刻度点。此形状对外声明一个极小的占用尺寸以通过密度检查，
/// 实际仍按正常半径绘制小圆点（与 5/15 档滑杆的刻度观感一致）。
class DenseSliderTickMarkShape extends SliderTickMarkShape {
  /// 实际绘制的圆点半径（逻辑像素）
  final double radius;

  const DenseSliderTickMarkShape({this.radius = 1.4});

  @override
  Size getPreferredSize({
    required bool isEnabled,
    required SliderThemeData sliderTheme,
  }) {
    // 故意极小：让「间距 / 声明的刻度宽」通过密度检查（阈值 3.0px）
    return const Size(1.0, 1.0);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    required bool isEnabled,
  }) {
    // 颜色逻辑与 RoundSliderTickMarkShape 一致：拇指右侧用未播放色，
    // 左侧用已播放色（按文本方向区分）
    final double xOffset = center.dx - thumbCenter.dx;
    final (Color? begin, Color? end) = switch (textDirection) {
      TextDirection.ltr when xOffset > 0 => (
        sliderTheme.disabledInactiveTickMarkColor,
        sliderTheme.inactiveTickMarkColor,
      ),
      TextDirection.rtl when xOffset < 0 => (
        sliderTheme.disabledInactiveTickMarkColor,
        sliderTheme.inactiveTickMarkColor,
      ),
      TextDirection.ltr || TextDirection.rtl => (
        sliderTheme.disabledActiveTickMarkColor,
        sliderTheme.activeTickMarkColor,
      ),
    };
    final paint = Paint()
      ..color = ColorTween(begin: begin, end: end).evaluate(enableAnimation)!;
    if (radius > 0) {
      context.canvas.drawCircle(center, radius, paint);
    }
  }
}

/// 分组标题（如「外观」「播放」）
class SettingsGroupTitle extends StatelessWidget {
  final String title;

  const SettingsGroupTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 圆角设置卡片容器（一组设置项）
class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const SettingsCard({super.key, required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 设置项行：图标容器 + 标题 + 可选副标题 + 尾部（默认 chevron）
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
      ),
      title: Text(
        title,
        // 主标题字号大于副标题（ListTile 默认副标题 14），形成清晰视觉层级
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle,
      trailing: trailing ?? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }
}

/// 多选设置项行（复选框，可同时勾选多项；工作.md 阶段1 第 1 点顶部信息多选）
class SettingsCheckboxTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  const SettingsCheckboxTile({
    super.key,
    required this.icon,
    required this.title,
    required this.checked,
    this.subtitle,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: checked ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: checked ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle,
      trailing: Checkbox(
        value: checked,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      ),
    );
  }
}

/// 单选设置项行（trailing 显示选中勾）
class SettingsRadioTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const SettingsRadioTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle,
      trailing: selected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : Icon(Icons.circle_outlined, color: scheme.outlineVariant),
    );
  }
}
