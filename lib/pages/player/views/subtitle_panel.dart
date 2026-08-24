import 'package:flutter/material.dart';
import 'package:moumou/models/subtitle_track.dart';
import 'package:moumou/pages/player/views/subtitle_file_picker.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/subtitle_service.dart';
import 'package:moumou/services/subtitle_settings.dart';
import 'package:moumou/widgets/player_panel.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 字幕面板：播放器内「字幕」右侧滑入。
///
/// **一级面板直接集成两个板块**（不做二级菜单）：
/// - **字幕轨道 + 外挂字幕**：融合板块——当前可用轨道列表（单选：点击选中/再点关闭，
///   选中态高亮 + 对勾清晰可见；外挂轨道带「移除」按钮）+「导入外部字幕」；
/// - **字幕设置**：四个入口（字幕延迟 / 字幕样式 / 字幕杂项 / 字幕字体），
///   各自进入面板内二级页。
///
/// 面板共用 [SubtitleController]（横竖屏共享同一实例）与 [SubtitleSettings]。
///
/// [onPushSubPage]：面板内二级页就地切换回调——横屏页传 [PlayerPanelNavigator]、
/// 竖屏页传 [PlayerBottomPanelNavigator] 的 push（两套外壳导航器不同类，由页面注入；
/// §4.5 约定：必须用面板树内的 context，页面侧用 Builder 包裹）。
class PlayerSubtitlePanel extends StatelessWidget {
  final SubtitleController controller;

  /// 面板内二级页推页回调（页面注入，避免面板依赖具体外壳导航器）
  final void Function(String title, Widget body)? onPushSubPage;

  /// 面板内二级页 pop 回调（文件选择器选完/关闭后返回上一级用）
  final VoidCallback? onPopSubPage;

  const PlayerSubtitlePanel({
    super.key,
    required this.controller,
    this.onPushSubPage,
    this.onPopSubPage,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, SubtitleSettings.instance]),
      builder: (context, _) {
        final tracks = controller.tracks;
        final primary = controller.primary;
        final hasSelection = primary != null;
        return ListView(
          key: const PageStorageKey('subtitle_main'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            // ── 字幕轨道（单选）──────────────────────────
            const _SectionLabel('字幕轨道'),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '当前视频没有字幕，可在下方导入外挂字幕',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              for (final t in tracks)
                _TrackTile(
                  track: t,
                  selected: primary?.id == t.id,
                  onTap: () => controller.cycleSelection(t),
                  onRemove: t.external
                      ? () => controller.removeExternalSubtitle(t)
                      : null,
                ),
            if (hasSelection)
              ListTile(
                dense: true,
                leading: const Icon(Icons.closed_caption_off_outlined,
                    color: Colors.white54, size: 22),
                title: const Text(
                  '关闭字幕',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () => controller.selectTrack(null),
              ),
            // ── 外挂字幕 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('外挂字幕'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_upload_outlined,
                  color: Colors.white, size: 22),
              title: const Text(
                '导入外部字幕',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: const Text(
                'srt / ass / ssa / vtt 等格式（退出播放后仍会记住）',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => _importExternalSubtitle(context),
            ),
            // ── 字幕设置 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('字幕设置'),
            _SubtitleSettingsEntry(
              icon: Icons.timer_outlined,
              label: '字幕延迟',
              subtitle: '点按秒数直接输入，或快捷调整',
              onTap: () => _pushSubPage(
                context,
                '字幕延迟',
                SubtitleDelayPanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.format_size,
              label: '字幕样式',
              subtitle: '颜色、描边模式、粗细、重置',
              onTap: () => _pushSubPage(
                context,
                '字幕样式',
                SubtitleStylePanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.vertical_align_center,
              label: '字幕杂项',
              subtitle: '缩放比例与垂直位置',
              onTap: () => _pushSubPage(
                context,
                '字幕杂项',
                SubtitleMiscPanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.font_download_outlined,
              label: '字幕字体',
              subtitle: '选择字幕渲染字体',
              onTap: () => _pushSubPage(
                context,
                '字幕字体',
                SubtitleFontPanel(
                  controller: controller,
                  onPushSubPage: onPushSubPage,
                  onCloseSubPage: onPopSubPage,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 面板内二级页就地切换（§4.5：复用面板导航器，禁止叠加第二个面板）。
  /// 由页面注入的 [onPushSubPage] 执行具体外壳的 push。
  void _pushSubPage(BuildContext context, String title, Widget body) {
    final push = onPushSubPage;
    if (push != null) {
      push(title, body);
      return;
    }
    // 兑底：无注入时尝试右侧面板导航器（横屏外壳）
    PlayerPanelNavigator.of(context)
        .push(PlayerPanelPage(title: title, body: body));
  }

  /// 导入外挂字幕：按 Android 版本走系统/自建文件选择器。
  /// - SDK ≤ 30：系统选择器（原生 ACTION_OPEN_DOCUMENT）；
  /// - SDK ≥ 31：自建选择器（[SubtitleFilePickerPanel]，右侧面板二级页）。
  Future<void> _importExternalSubtitle(BuildContext context) async {
    final sdk = await DeviceServices.getSdkInt();
    if (!context.mounted || sdk <= 0) return;
    if (sdk <= 30) {
      final path = await SubtitleFileService.pickWithSystemPicker();
      if (path == null || !context.mounted) return;
      await _importPath(context, path);
      return;
    }
    // 自建选择器：作为右侧面板二级页就地切换（不再从底部弹出）
    _pushSubPage(
      context,
      '选择字幕文件',
      SubtitleFilePickerPanel(
        onPicked: (path) async {
          await controller.addExternalSubtitle(path);
        },
        onClose: () => onPopSubPage?.call(),
      ),
    );
  }

  /// 导入并给出轻提示（系统选择器路径用；自建选择器返回后由轨道列表刷新体现）
  Future<void> _importPath(BuildContext context, String path) async {
    final ok = await controller.addExternalSubtitle(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? '已导入外挂字幕' : '导入失败，请检查文件格式'),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// 字幕轨道行（单选）：当前生效的轨道高亮 + 对勾；外挂轨道带「移除」按钮。
class _TrackTile extends StatelessWidget {
  final SubtitleTrack track;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4FC3F7);
    return ListTile(
      dense: true,
      leading: Icon(
        track.external
            ? (selected
                ? Icons.subtitles_rounded
                : Icons.subtitles_outlined)
            : (selected
                ? Icons.closed_caption_rounded
                : Icons.closed_caption_outlined),
        color: selected ? accent : Colors.white54,
        size: 22,
      ),
      title: Text(
        subtitleTrackLabel(track),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 20),
              tooltip: '移除已导入的字幕',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
            ),
          if (selected)
            const Icon(Icons.check_circle, color: accent, size: 20)
          else
            const SizedBox(width: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 面板内小节标题
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 字幕设置入口行
class _SubtitleSettingsEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SubtitleSettingsEntry({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 22),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}

// ────────────────────────────────────────────────────────────
// 通用样式（与设置页共用 Kazumi 滑杆外观）
// ────────────────────────────────────────────────────────────

/// 面板内统一强调色
const Color _accent = Color(0xFF4FC3F7);

/// 字幕面板用的暗色 ColorScheme（供 kazumiSliderTheme 复用设置页滑杆外观）
final ColorScheme _panelScheme = ColorScheme.fromSeed(
  seedColor: _accent,
  brightness: Brightness.dark,
);

/// 与「设置」页面一致的滑杆主题（Kazumi 风格：缺口轨道 + 小柄拇指）
SliderThemeData _panelSliderTheme() => kazumiSliderTheme(_panelScheme);

/// 面板内圆角卡片容器（与设置页 SettingsCard 视觉一致，暗色适配）
class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// 卡片内行标签
class _CardLabel extends StatelessWidget {
  final String text;

  const _CardLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 通用设置滑杆（Kazumi 外观）：读数居左 / 滑杆跟随。
class _SettingSlider extends StatelessWidget {
  final String label;
  final String display;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _SettingSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: _panelSliderTheme(),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value.clamp(min, max),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 字幕延迟（工作.md 阶段1 第 3 点）
// ────────────────────────────────────────────────────────────

/// 字幕延迟二级页：顶部的秒数胶囊「既是显示、也是输入框」
/// （点按直接改数字 → 回车应用），下方保留快捷调整按键与重置。
class SubtitleDelayPanel extends StatefulWidget {
  final SubtitleController controller;

  const SubtitleDelayPanel({super.key, required this.controller});

  @override
  State<SubtitleDelayPanel> createState() => _SubtitleDelayPanelState();
}

class _SubtitleDelayPanelState extends State<SubtitleDelayPanel> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _input.text = _delayText(SubtitleSettings.instance.delay);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 快捷调整：改设置 + 应用；输入框文本由 ListenableBuilder 刷新
  Future<void> _adjust(double delta) async {
    await SubtitleSettings.instance.adjustDelay(delta);
    await widget.controller.applyAllSettings();
  }

  /// 手动输入秒数并应用（非法输入忽略）
  Future<void> _applyInput() async {
    final v = double.tryParse(_input.text.trim());
    if (v == null) return;
    await SubtitleSettings.instance.setDelay(v);
    await widget.controller.applyAllSettings();
    if (!mounted) return;
    _focus.unfocus();
  }

  /// 重置为 0（await 保证先改设置再应用，修复“重置后延迟效果仍在”的竞态 bug）
  Future<void> _reset() async {
    await SubtitleSettings.instance.setDelay(0);
    await widget.controller.applyAllSettings();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        // 外部改动（快捷按键/重置）时同步输入框文本（输入中不打断）
        if (!_focus.hasFocus) {
          final text = _delayText(settings.delay);
          if (_input.text != text) _input.text = text;
        }
        final delay = settings.delay;
        return ListView(
          key: const PageStorageKey('subtitle_delay'),
          padding: const EdgeInsets.all(16),
          children: [
            // 显示 + 输入合二为一的胶囊
            TextField(
              controller: _input,
              focusNode: _focus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.10),
                hintText: _delayText(delay),
                hintStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: _accent),
                ),
              ),
              onTap: () => _input.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _input.text.length,
              ),
              onSubmitted: (_) => _applyInput(),
            ),
            const SizedBox(height: 6),
            Text(
              '点按上方秒数可直接输入修改（延后为正、提前为负，范围 -60 ~ +60 秒）',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('快捷调整（可叠加）'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _DelayButton(label: '-1.0s', onTap: () => _adjust(-1.0)),
                _DelayButton(label: '-0.5s', onTap: () => _adjust(-0.5)),
                _DelayButton(label: '+0.5s', onTap: () => _adjust(0.5)),
                _DelayButton(label: '+1.0s', onTap: () => _adjust(1.0)),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: delay == 0 ? null : _reset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置为 0 秒'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ],
        );
      },
    );
  }

  static String _delayText(double delay) {
    final sign = delay > 0 ? '+' : '';
    final text = delay == delay.roundToDouble()
        ? delay.toInt().toString()
        : delay.toStringAsFixed(1);
    return '$sign$text 秒';
  }
}

/// 延迟快捷调整键（胶囊）
class _DelayButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DelayButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 字幕样式（工作.md 阶段1 第 3 点；布局参考 mpvRx/小喵：颜色集中 + 描边模式）
// ────────────────────────────────────────────────────────────

/// 字幕样式二级页：
/// 1. **字幕颜色**卡片：文字/描边/背景颜色集中在一块，预设色点 + 展开 RGBA 滑杆；
/// 2. **描边模式**卡片：无 / 描边 / 背景框 三选一，带当前模式调节指引；
/// 3. **描边粗细**（描边模式时显示）：滑杆 + 重置默认；
/// 4. **文字效果**卡片：粗体 / 斜体 / 字间距 / 模糊；
/// 5. **强制覆盖内嵌样式**开关 + 不生效提示 + **重置所有样式**。
class SubtitleStylePanel extends StatelessWidget {
  final SubtitleController controller;

  const SubtitleStylePanel({super.key, required this.controller});

  Future<void> _apply(String? color, SubtitleSettings s,
      void Function(String?) setter) async {
    setter(color);
    await controller.applyAllSettings();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final mode = settings.borderStyle;
        return ListView(
          key: const PageStorageKey('subtitle_style'),
          padding: const EdgeInsets.all(16),
          children: [
            // ── 字幕颜色（集中一块）────────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ColorEditorRow(
                    label: '文字颜色',
                    value: settings.color,
                    allowNone: false,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setColor(v ?? '#FFFFFF')),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _ColorEditorRow(
                    label: '描边颜色',
                    value: settings.borderColor,
                    allowNone: true,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setBorderColor(v)),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _ColorEditorRow(
                    label: '背景颜色',
                    value: settings.backColor,
                    allowNone: true,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setBackColor(v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 描边模式 ─────────────────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('描边模式'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        for (final m in SubtitleBorderStyle.values) ...[
                          if (m != SubtitleBorderStyle.values.first)
                            const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                settings.setBorderStyle(m);
                                controller.applyAllSettings();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: mode == m
                                      ? _accent
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: mode == m
                                        ? Colors.black
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Text(
                      _modeHint(mode),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── 描边粗细（仅「描边」模式）────────────
            if (mode == SubtitleBorderStyle.outline) ...[
              const SizedBox(height: 16),
              _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingSlider(
                      label: '描边粗细',
                      display: settings.borderSize.toStringAsFixed(1),
                      value: settings.borderSize,
                      min: 0,
                      max: 10,
                      divisions: 40,
                      onChanged: (v) {
                        settings.setBorderSize(v);
                        controller.applyAllSettings();
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: settings.borderSize == 2.5
                            ? null
                            : () {
                                settings.setBorderSize(2.5);
                                controller.applyAllSettings();
                              },
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('重置默认'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // ── 文字效果 ─────────────────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('文字效果'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeThumbColor: _accent,
                            title: const Text('粗体',
                                style: TextStyle(color: Colors.white, fontSize: 14)),
                            value: settings.bold,
                            onChanged: (v) {
                              settings.setBold(v);
                              controller.applyAllSettings();
                            },
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeThumbColor: _accent,
                            title: const Text('斜体',
                                style: TextStyle(color: Colors.white, fontSize: 14)),
                            value: settings.italic,
                            onChanged: (v) {
                              settings.setItalic(v);
                              controller.applyAllSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _SettingSlider(
                    label: '字间距',
                    display: settings.spacing.toStringAsFixed(1),
                    value: settings.spacing,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    onChanged: (v) {
                      settings.setSpacing(v);
                      controller.applyAllSettings();
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _SettingSlider(
                    label: '模糊',
                    display: settings.blur.toStringAsFixed(1),
                    value: settings.blur,
                    min: 0,
                    max: 20,
                    divisions: 40,
                    onChanged: (v) {
                      settings.setBlur(v);
                      controller.applyAllSettings();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 强制覆盖内嵌样式 ─────────────────────
            _PanelCard(
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                activeThumbColor: _accent,
                title: const Text(
                  '强制覆盖内嵌样式',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: Text(
                  settings.overrideEmbeddedStyle
                      ? '已开启：用上方设置渲染所有字幕（含内嵌样式字幕）'
                      : '已关闭：内嵌字幕使用其自带的样式与字体',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                value: settings.overrideEmbeddedStyle,
                onChanged: (v) {
                  settings.setOverrideEmbeddedStyle(v);
                  controller.applyAllSettings();
                },
              ),
            ),
            const SizedBox(height: 12),
            // ── 不生效提示 ───────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4A3A13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6B5618)),
              ),
              child: const Text(
                '提示：调整样式后若不生效，通常是以下原因——\n'
                '① 当前是 ASS/SSA 内嵌字幕且未开启「强制覆盖内嵌样式」，请开启该开关；\n'
                '② 字幕自带内联样式标签（inline tag）时，全局样式无法覆盖，请改用不含内联标签的字幕；\n'
                '③ 请确认已选中字幕轨道（面板顶部勾选）。',
                style: TextStyle(color: Color(0xFFFFE082), fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            // ── 重置所有样式 ─────────────────────────
            FilledButton.tonalIcon(
              onPressed: () async {
                await settings.resetStyles();
                await controller.applyAllSettings();
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置所有样式'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 描边模式下该调节什么的指引文案
  static String _modeHint(SubtitleBorderStyle mode) => switch (mode) {
        SubtitleBorderStyle.none =>
          '当前无描边、无背景框，仅显示文字颜色（在上方「文字颜色」调节）。',
        SubtitleBorderStyle.outline =>
          '经典描边：在上方「描边颜色」选色，用下方「描边粗细」滑块调整粗细。',
        SubtitleBorderStyle.box =>
          '字幕后方背景框：在上方「背景颜色」选色，拖动 A 通道可调透明度。',
      };
}

/// 把 mpv 颜色串（`#RRGGBB` / `#AARRGGBB`，8 位时 alpha 在前）转成 Flutter
/// [Color]（同样为 ARGB）。
Color colorFromMpvHex(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

/// 单个颜色的编辑行：标题 + 预设色点 + 「自定义」展开 RGBA 滑杆。
///
/// 预设/自定义两态切换带 [AnimatedSize] 平滑过渡；
/// RGBA 四个通道滑杆与设置页同款外观。
class _ColorEditorRow extends StatefulWidget {
  final String label;
  final String? value;
  final bool allowNone;
  final ValueChanged<String?> onSelect;

  const _ColorEditorRow({
    required this.label,
    required this.value,
    this.allowNone = false,
    required this.onSelect,
  });

  @override
  State<_ColorEditorRow> createState() => _ColorEditorRowState();
}

class _ColorEditorRowState extends State<_ColorEditorRow> {
  bool _custom = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.value != null
        ? mpvColorToRgba(widget.value!)
        : const (r: 255, g: 255, b: 255, a: 255);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.value == null
                      ? Colors.black26
                      : colorFromMpvHex(widget.value!),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.value == null
                        ? Colors.white24
                        : Colors.white38,
                  ),
                ),
                child: widget.value == null
                    ? const Icon(Icons.block, size: 13, color: Colors.white70)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              // 自定义开关（带动画旋转的箭头）
              GestureDetector(
                onTap: () => setState(() => _custom = !_custom),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _custom
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          _custom ? _accent : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _custom ? '收起' : '自定义',
                        style: TextStyle(
                          color: _custom ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _custom ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down,
                            size: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 预设 / RGBA 两态切换（动画过渡）
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _custom ? _buildChannels(base) : _buildPresets(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 预设色点（允许「无」）
  Widget _buildPresets() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (widget.allowNone)
            _ColorDot(
              hex: null,
              label: '无',
              selected: widget.value == null,
              onTap: () => widget.onSelect(null),
            ),
          for (final c in SubtitlePresetColor.presets)
            _ColorDot(
              hex: c.hex,
              label: c.label,
              selected: _matchesPreset(c.hex),
              onTap: () => widget.onSelect(c.hex),
            ),
          // 当前生效色（非预设时也可见）
          if (widget.value != null && !_matchesAnyPreset(widget.value!))
            _ColorDot(
              hex: widget.value,
              label: '当前',
              selected: true,
              onTap: null,
            ),
        ],
      ),
    );
  }

  bool _matchesPreset(String hex) {
    if (widget.value == null) return false;
    final a = mpvColorToRgba(widget.value!);
    final b = mpvColorToRgba(hex);
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == 255;
  }

  bool _matchesAnyPreset(String hex) {
    for (final c in SubtitlePresetColor.presets) {
      if (_matchesPreset(c.hex)) return true;
    }
    return false;
  }

  /// RGBA 四通道滑杆
  Widget _buildChannels(SubtitleRgba base) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          _ChannelSlider(
            label: 'R',
            trackColor: const Color(0xFFE53935),
            value: base.r,
            onChanged: (v) => widget.onSelect(
              rgbaToMpvColor((r: v, g: base.g, b: base.b, a: base.a)),
            ),
          ),
          _ChannelSlider(
            label: 'G',
            trackColor: const Color(0xFF43A047),
            value: base.g,
            onChanged: (v) => widget.onSelect(
              rgbaToMpvColor((r: base.r, g: v, b: base.b, a: base.a)),
            ),
          ),
          _ChannelSlider(
            label: 'B',
            trackColor: const Color(0xFF1E88E5),
            value: base.b,
            onChanged: (v) => widget.onSelect(
              rgbaToMpvColor((r: base.r, g: base.g, b: v, a: base.a)),
            ),
          ),
          _ChannelSlider(
            label: 'A',
            trackColor: const Color(0xFF9E9E9E),
            value: base.a,
            onChanged: (v) => widget.onSelect(
              rgbaToMpvColor((r: base.r, g: base.g, b: base.b, a: v)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预设色点（小圆 + 名称；当前选中带勾）
class _ColorDot extends StatelessWidget {
  final String? hex;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ColorDot({
    this.hex,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _accent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: hex == null ? Colors.black26 : colorFromMpvHex(hex!),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30),
              ),
              child: hex == null
                  ? const Icon(Icons.block, size: 11, color: Colors.white70)
                  : (selected
                      ? const Icon(Icons.check, size: 11, color: Colors.black54)
                      : null),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// RGBA 单个通道滑杆（设置页同款外观），左侧通道色块 + 读数。
class _ChannelSlider extends StatelessWidget {
  final String label;
  final Color trackColor;
  final int value;
  final ValueChanged<int> onChanged;

  const _ChannelSlider({
    required this.label,
    required this.trackColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              color: trackColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: _panelSliderTheme().copyWith(
              activeTrackColor: trackColor,
              thumbColor: trackColor,
            ),
            child: Slider(
              min: 0,
              max: 255,
              divisions: 255,
              value: value.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 字幕杂项（工作.md 阶段1 第 3 点）
// ────────────────────────────────────────────────────────────

/// 字幕杂项二级页：仅保留 缩放比例 + 垂直位置（对齐/边距按需去掉，
/// 默认居中对齐即可）。
///
/// 说明：`sub-pos`（垂直位置）对 ASS 也生效（margin 机制），
/// `sub-scale`（缩放）对普通文本字幕恒生效；对 ASS 字幕是否生效取决于
/// 内嵌样式模式（对应 mpv `sub-ass-override`），强制覆盖开启时必然生效。
class SubtitleMiscPanel extends StatelessWidget {
  final SubtitleController controller;

  const SubtitleMiscPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return ListView(
          key: const PageStorageKey('subtitle_misc'),
          padding: const EdgeInsets.all(16),
          children: [
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('字幕缩放与位置'),
                  _SettingSlider(
                    label: '缩放比例',
                    display: '${settings.scale.toStringAsFixed(2)}x',
                    value: settings.scale,
                    min: SubtitleSettings.minScale,
                    max: SubtitleSettings.maxScale,
                    divisions: 25,
                    onChanged: (v) {
                      settings.setScale(v);
                      controller.applyAllSettings();
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _SettingSlider(
                    label: '垂直位置',
                    display: '${settings.position.round()}（100=底部）',
                    value: settings.position,
                    min: SubtitleSettings.minPos,
                    max: SubtitleSettings.maxPos,
                    divisions: 100,
                    onChanged: (v) {
                      settings.setPosition(v);
                      controller.applyAllSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
// 字幕字体（工作.md 阶段1 第 3 点）
// ────────────────────────────────────────────────────────────

/// 字幕字体二级页：跟随默认 + 导入自己的字体（.ttf/.otf）+ 已导入字体列表。
///
/// 字体选择（参考小喵：让用户进文件夹选字体文件再拷贝）：
/// - SDK ≤ 30：系统选择器（字体 MIME，不再置灰）；
/// - SDK ≥ 31：自建文件夹选择器（[SubtitleFilePickerPanel] 过滤 .ttf/.otf）。
class SubtitleFontPanel extends StatelessWidget {
  final SubtitleController controller;

  /// 面板内二级页推页回调（字体自建选择器用）
  final void Function(String title, Widget body)? onPushSubPage;

  /// 面板内二级页 pop 回调
  final VoidCallback? onCloseSubPage;

  const SubtitleFontPanel({
    super.key,
    required this.controller,
    this.onPushSubPage,
    this.onCloseSubPage,
  });

  Future<void> _import(BuildContext context) async {
    final sdk = await DeviceServices.getSdkInt();
    if (!context.mounted || sdk <= 0) return;
    if (sdk <= 30) {
      final path = await DeviceServices.importFontFile();
      if (path == null || !context.mounted) return;
      await SubtitleSettings.instance.importFont(path);
      await controller.applyAllSettings();
      return;
    }
    // 自建选择器：只显示 .ttf/.otf/.ttc，选中文件后把真实路径当作字体导入
    final push = onPushSubPage;
    if (push == null) return;
    push(
      '选择字体文件',
      SubtitleFilePickerPanel(
        fileFilter: isFontFile,
        onPicked: (path) async {
          await SubtitleSettings.instance.importFont(path);
          await controller.applyAllSettings();
        },
        onClose: () => onCloseSubPage?.call(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final current = settings.font;
        final imported = settings.importedFonts;
        return ListView(
          key: const PageStorageKey('subtitle_font'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            _FontTile(
              label: '跟随默认',
              selected: current == 'auto',
              onTap: () {
                settings.setFont('auto');
                controller.applyAllSettings();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined,
                  color: Colors.white, size: 22),
              title: const Text(
                '导入字体',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                '.ttf / .otf（选择字体所在文件夹，自动拷贝）',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => _import(context),
            ),
            if (imported.isNotEmpty) ...[
              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '已导入字体',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              for (final f in imported)
                _ImportedFontTile(
                  name: _fontDisplayName(f),
                  selected: current == f,
                  onSelect: () {
                    settings.setFont(f);
                    controller.applyAllSettings();
                  },
                  onDelete: () {
                    settings.removeFont(f);
                    controller.applyAllSettings();
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

/// 字体文件路径 → 展示名（去掉目录）
String _fontDisplayName(String path) {
  final segs = path.split('/');
  return segs.isEmpty ? path : segs.last;
}

/// 「跟随默认」字体选项行
class _FontTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FontTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? _accent : Colors.white38,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// 已导入字体选项行（可删除）
class _ImportedFontTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ImportedFontTile({
    required this.name,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? _accent : Colors.white38,
        size: 20,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
        tooltip: '删除',
        onPressed: onDelete,
      ),
      onTap: onSelect,
    );
  }
}