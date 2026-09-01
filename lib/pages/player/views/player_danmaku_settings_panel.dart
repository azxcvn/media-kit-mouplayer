/// 弹幕设置面板（阶段2，工作.md 弹幕第 4 点）：两个部分组成——
///
/// **弹幕样式**：字号 / 字重 / 描边粗细为「重栅格化」项（松手才提交，
/// 见 [_CommitSliderTile]）+ 速度 / 不透明度（无极滑杆，实时生效）+
/// 随机渐变色开关（开启后忽略弹幕文件内颜色，所有弹幕按 HSV 色轮黄金角
/// 渐变随机着色，算法见 utils/danmaku_random_color.dart）；
///
/// **弹幕配置**：显示区域 / 行高滑杆 + 顶部/底部/滚动弹幕显隐开关 +
/// 海量弹幕开关（轨道占满时叠加绘制）+ 弹幕去重开关（时间窗内相同
/// 内容合并为一条）。
///
/// **弹幕偏移**：时间轴偏移滑杆（-180~+180 秒，正 = 延后、负 = 提前），
/// 校准弹幕相对视频画面的显示时间（对齐 Kazumi danmakuTimeOffset）。
///
/// 所有设置持久化于 [DanmakuSettings]（全局单例），重启视频/重启播放/
/// 重启软件均保留（工作.md 弹幕第 6 点）；面板与 [DanmakuController]
/// 共同监听设置单例，改值即时生效无需重开面板。
///
/// 横屏在 [showPlayerPanel] 右侧滑入外壳、竖屏在 [showPlayerBottomPanel]
/// 底部弹出外壳共用本内容（§4.5 约定）；入口：横屏左下角时间右侧的
/// 弹幕设置按钮 / 竖屏右下角进度条上方的弹幕设置按钮 / 更多→弹幕→弹幕设置
/// （三处入口进入同一面板，工作.md 弹幕第 2 点）。
library;

import 'package:flutter/material.dart';
import 'package:moumou/models/danmaku_font_mode.dart';
import 'package:moumou/services/app_font_settings.dart';
import 'package:moumou/services/danmaku_settings.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/utils/danmaku_timeline.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// FontWeight.values 下标 → 中文名称（字重滑杆读数）
const List<String> _fontWeightNames = [
  '极细',
  '很细',
  '细',
  '常规',
  '中等',
  '较粗',
  '粗',
  '很粗',
  '极粗',
];

/// 与「设置」页面 / 字幕面板一致的滑杆主题（Kazumi 风格：缺口轨道 + 小柄
/// 拇指，无拖拽气泡——用户要的「字幕杂项」那种，而非默认大圆钮 + 气泡）。
///
/// **跟随主题**：强调色由 [playerPanelSliderTheme] 从当前 `ColorScheme.primary`
/// 派生暗色方案得到（原实现用写死的 `Color(0xFF4FC3F7)`，换主题色滑杆不变）。
SliderThemeData _panelSliderTheme(BuildContext context) =>
    playerPanelSliderTheme(context);

class PlayerDanmakuSettingsPanel extends StatelessWidget {
  const PlayerDanmakuSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DanmakuSettings.instance,
      builder: (context, _) {
        final s = DanmakuSettings.instance;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('弹幕样式'),
              _SettingsGroup(children: [
                _CommitSliderTile(
                  label: '弹幕字号',
                  value: s.fontSize,
                  min: DanmakuSettings.minFontSize,
                  max: DanmakuSettings.maxFontSize,
                  display: (v) => v.round().toString(),
                  onCommit: s.setFontSize,
                ),
                _groupDivider(),
                _CommitSliderTile(
                  label: '字体字重',
                  value: s.fontWeight.toDouble(),
                  min: DanmakuSettings.minFontWeight,
                  max: DanmakuSettings.maxFontWeight,
                  display: (v) => _fontWeightNames[v.round()],
                  // 字重取整档（w100–w900 九档，滑杆无极拖动松手即最近档）
                  divisions: 8,
                  onCommit: (v) => s.setFontWeight(v.round()),
                ),
                _groupDivider(),
                _SliderTile(
                  label: '弹幕速度',
                  value: s.scrollSeconds,
                  min: DanmakuSettings.minScrollSeconds,
                  max: DanmakuSettings.maxScrollSeconds,
                  display: '${s.scrollSeconds.round()} 秒',
                  hint: '数值越小弹幕越快',
                  onChanged: s.setScrollSeconds,
                ),
                _groupDivider(),
                _CommitSliderTile(
                  label: '描边粗细',
                  value: s.strokeWidth,
                  min: DanmakuSettings.minStrokeWidth,
                  max: DanmakuSettings.maxStrokeWidth,
                  display: (v) => v == 0 ? '无' : v.toStringAsFixed(1),
                  onCommit: s.setStrokeWidth,
                ),
                _groupDivider(),
                _SliderTile(
                  label: '不透明度',
                  value: s.opacity,
                  min: DanmakuSettings.minOpacity,
                  max: DanmakuSettings.maxOpacity,
                  display: '${(s.opacity * 100).round()}%',
                  onChanged: s.setOpacity,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '随机渐变色',
                  hint: '开启后忽略弹幕文件内颜色，全部使用随机渐变色',
                  value: s.randomColor,
                  onChanged: s.setRandomColor,
                ),
              ]),
              const SizedBox(height: 16),
              const _SectionLabel('弹幕配置'),
              _SettingsGroup(children: [
                _SliderTile(
                  label: '显示区域',
                  value: s.area,
                  min: DanmakuSettings.minArea,
                  max: DanmakuSettings.maxArea,
                  display: '${(s.area * 100).round()}%',
                  onChanged: s.setArea,
                ),
                _groupDivider(),
                _SliderTile(
                  label: '弹幕行高',
                  value: s.lineHeight,
                  min: DanmakuSettings.minLineHeight,
                  max: DanmakuSettings.maxLineHeight,
                  display: s.lineHeight.toStringAsFixed(1),
                  onChanged: s.setLineHeight,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '顶部弹幕',
                  value: s.showTop,
                  onChanged: s.setShowTop,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '底部弹幕',
                  value: s.showBottom,
                  onChanged: s.setShowBottom,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '滚动弹幕',
                  value: s.showScroll,
                  onChanged: s.setShowScroll,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '海量弹幕',
                  hint: '轨道占满时叠加绘制，弹幕过多不再丢弃',
                  value: s.massiveMode,
                  onChanged: s.setMassiveMode,
                ),
                _groupDivider(),
                _SwitchTile(
                  label: '弹幕去重',
                  hint: '时间窗内相同弹幕内容合并为一条',
                  value: s.deduplication,
                  onChanged: s.setDeduplication,
                ),
              ]),
              const SizedBox(height: 16),
              const _SectionLabel('弹幕偏移'),
              _SettingsGroup(children: [
                _CommitSliderTile(
                  label: '时间轴偏移',
                  value: s.timeOffsetSeconds,
                  min: DanmakuSettings.minTimeOffsetSeconds,
                  max: DanmakuSettings.maxTimeOffsetSeconds,
                  display: formatDanmakuTimeOffset,
                  // 1 秒一档（-180~+180 共 360 档），松手提交重锚定弹幕
                  divisions: 360,
                  onCommit: s.setTimeOffset,
                ),
                _groupDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _OffsetActionButton(
                          icon: Icons.remove,
                          label: '提前 1 秒',
                          enabled: s.timeOffsetSeconds >
                              DanmakuSettings.minTimeOffsetSeconds,
                          onTap: () =>
                              s.setTimeOffset(s.timeOffsetSeconds - 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OffsetActionButton(
                          icon: Icons.add,
                          label: '延后 1 秒',
                          enabled: s.timeOffsetSeconds <
                              DanmakuSettings.maxTimeOffsetSeconds,
                          onTap: () =>
                              s.setTimeOffset(s.timeOffsetSeconds + 1),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: _OffsetActionButton(
                      icon: Icons.restart_alt,
                      label: '重置偏移',
                      enabled: s.timeOffsetSeconds != 0,
                      onTap: () => s.setTimeOffset(0),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              const _SectionLabel('弹幕字体'),
              // 不能加 const：否则父级 ListenableBuilder 重建时该子组件因
              // 同实例被跳过 build，切换字体模式后单选选中态/自定义段不刷新
              _DanmakuFontSection(),
              const SizedBox(height: 16),
              _ResetButton(onTap: () => DanmakuSettings.instance.reset()),
            ],
          ),
        );
      },
    );
  }

  /// 组内分隔线（与播放器设置分组卡一致：1px 缩进线）
  static Widget _groupDivider() => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
        color: Colors.white10,
      );
}

/// 分组标题（如「弹幕样式」「弹幕配置」）
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 暗底圆角分组容器（面板内卡片，内容为滑杆/开关行 + 缩进分隔线）
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 无极滑杆行：标签 + 右侧实时读数 → 滑杆（拖动实时写设置，轻量项）。
class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final String? hint;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          // 与字幕面板「字幕杂项」一致的滑杆（Kazumi 2024 新式外观，无拖拽气泡）
          SliderTheme(
            data: _panelSliderTheme(context),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 重栅格化项滑杆（字号/字重/描边）：拖动时只改本地预览值（不触发 canvas
/// 重绘），松手时才提交到 [DanmakuSettings]（触发一次全量重绘）。避免
/// onChanged 逐像素全量重绘导致掉帧（对齐弹幕移植方案「松手才 updateOption」
/// 纪律）；轻量项仍走 [_SliderTile] 实时下发。
class _CommitSliderTile extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) display;
  final int? divisions;
  final ValueChanged<double> onCommit;

  const _CommitSliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
    this.divisions,
  });

  @override
  State<_CommitSliderTile> createState() => _CommitSliderTileState();
}

class _CommitSliderTileState extends State<_CommitSliderTile> {
  late double _preview = widget.value;

  @override
  void didUpdateWidget(_CommitSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部提交（如恢复默认）后同步预览值，避免滑杆停留在旧值
    if (oldWidget.value != widget.value && widget.value != _preview) {
      _preview = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              Text(
                widget.display(_preview),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _panelSliderTheme(context),
            child: Slider(
              value: _preview.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) => setState(() => _preview = v),
              onChangeEnd: widget.onCommit,
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹幕偏移的快捷操作按钮（提前/延后 1 秒 + 单独重置），紧凑胶囊样式，
/// 禁用态降透明度并阻断点击。
class _OffsetActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _OffsetActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 开关行：标签（+ 可选说明）→ 右侧 Switch
class _SwitchTile extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      hint!,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  )
                else
                  const SizedBox(height: 6),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 一键恢复默认（红色胶囊，对齐片头片尾面板的重置按钮样式）
class _ResetButton extends StatefulWidget {
  final VoidCallback onTap;

  const _ResetButton({required this.onTap});

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _flash = false;

  void _handleTap() {
    setState(() => _flash = true);
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _flash = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _flash
              ? scheme.error
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '恢复默认设置',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _flash ? scheme.onError : scheme.error,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// 弹幕字体段（工作.md 第 4 点）：跟随系统 / 跟随 App / 自定义 三选一（互斥），
/// 选「自定义」时展开字体目录导入 + 字体列表选择。复用 filesDir/fonts/ 共享
/// 字体池（与字幕字体同目录，一次导入三处可用）。
class _DanmakuFontSection extends StatefulWidget {
  const _DanmakuFontSection();

  @override
  State<_DanmakuFontSection> createState() => _DanmakuFontSectionState();
}

class _DanmakuFontSectionState extends State<_DanmakuFontSection> {
  List<SubtitleFontEntry> _entries = const [];
  bool _loading = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _reloadEntries();
  }

  /// 重新扫描私有 fonts/ 目录（进入面板/导入后刷新字体列表）
  Future<void> _reloadEntries() async {
    final entries = await DeviceServices.listFontEntries();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// 选择字体目录 → 一次性拷贝全部字体 → 刷新列表
  Future<void> _pickDirectory() async {
    final uri = await DeviceServices.openFontDirectoryPicker();
    if (uri == null || !mounted) return;
    setState(() => _loading = true);
    final count = await DeviceServices.copyFontsFromDirectory(uri);
    final entries = await DeviceServices.listFontEntries();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = entries;
    });
    _toast('已导入 $count 个字体文件，共 ${entries.length} 种字体');
  }

  /// 选中弹幕自定义字体：写设置 + 注册进引擎（即时生效，冷启动再注册）
  Future<void> _selectFont(SubtitleFontEntry entry) async {
    await DanmakuSettings.instance.setCustomFont(entry.family, entry.file);
    await AppFontSettings.registerFontFile(entry.family, entry.file);
    if (!mounted) return;
    setState(() => _expanded = false);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = DanmakuSettings.instance;
    final mode = s.fontMode;
    final appFamily = AppFontSettings.instance.effectiveFamily;
    return _SettingsGroup(children: [
      _FontRadioTile(
        label: DanmakuFontMode.followSystem.label,
        selected: mode == DanmakuFontMode.followSystem,
        onTap: () => s.setFontMode(DanmakuFontMode.followSystem),
      ),
      PlayerDanmakuSettingsPanel._groupDivider(),
      _FontRadioTile(
        label: DanmakuFontMode.followApp.label,
        subtitle: appFamily,
        selected: mode == DanmakuFontMode.followApp,
        onTap: () => s.setFontMode(DanmakuFontMode.followApp),
      ),
      PlayerDanmakuSettingsPanel._groupDivider(),
      _FontRadioTile(
        label: DanmakuFontMode.custom.label,
        selected: mode == DanmakuFontMode.custom,
        onTap: () => s.setFontMode(DanmakuFontMode.custom),
      ),
      if (mode == DanmakuFontMode.custom) ...[
        PlayerDanmakuSettingsPanel._groupDivider(),
        _FontTile(
          icon: Icons.folder_open,
          title: '选择字体目录',
          subtitle: _loading
              ? '正在加载...'
              : (_entries.isEmpty
                  ? '点击导入包含 .ttf/.otf 字体的目录'
                  : '已加载 ${_entries.length} 种字体'),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: _loading ? null : _pickDirectory,
        ),
        if (_entries.isNotEmpty) ...[
          PlayerDanmakuSettingsPanel._groupDivider(),
          _FontTile(
            icon: Icons.text_fields,
            title: s.customFontFamily ?? '选择字体',
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white54,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          // 展开/收起动画（字幕字体面板同款 AnimatedSize）
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    children: [
                      for (final e in _entries)
                        _FontOptionTile(
                          label: e.family,
                          subtitle: e.file,
                          selected: s.customFontFamily == e.family,
                          onTap: () => _selectFont(e),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    ]);
  }
}

/// 弹幕字体三选一单选行（跟随系统 / 跟随 App / 自定义，互斥）
class _FontRadioTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _FontRadioTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = playerPanelAccent(context);
    // ListTile 外包 Material：_SettingsGroup 是带背景色的 Container，
    // 否则 ListTile 会因 DecoratedBox 遮挡 ink 而触发断言（§4.5 面板约定）
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        leading: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? accent : Colors.white24,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 13, color: Colors.black87)
              : null,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? accent : Colors.white,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
        onTap: onTap,
      ),
    );
  }
}

/// 弹幕自定义字体选项行（单选高亮）
class _FontOptionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _FontOptionTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = playerPanelAccent(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 28, right: 16),
        leading: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? accent : Colors.white24,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 12, color: Colors.black87)
              : null,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? accent : Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 弹幕字体段内的通用图标行（选择字体目录 / 选择字体）
class _FontTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _FontTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: Colors.white, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
