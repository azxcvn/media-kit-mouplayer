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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GestureDetector(
                  onTap: () => controller.selectTrack(null),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.closed_caption_off_outlined,
                            size: 16, color: Colors.white70),
                        SizedBox(width: 6),
                        Text(
                          '关闭字幕',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
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
              onTap: () => _importExternalSubtitle(context),
            ),
            // ── 字幕设置 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('字幕设置'),
            _SubtitleSettingsEntry(
              icon: Icons.timer_outlined,
              label: '字幕延迟',
              onTap: () => _pushSubPage(
                context,
                '字幕延迟',
                SubtitleDelayPanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.format_size,
              label: '字幕样式',
              onTap: () => _pushSubPage(
                context,
                '字幕样式',
                SubtitleStylePanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.vertical_align_center,
              label: '字幕杂项',
              onTap: () => _pushSubPage(
                context,
                '字幕杂项',
                SubtitleMiscPanel(controller: controller),
              ),
            ),
            _SubtitleSettingsEntry(
              icon: Icons.font_download_outlined,
              label: '字幕字体',
              onTap: () => _pushSubPage(
                context,
                '字幕字体',
                SubtitleFontPanel(controller: controller),
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

/// 字幕轨道行（单选）：统一 CC 图标，选中态以主题色高亮（不再打勾）；
/// 标题只显示干净的轨道名（外挂字幕去掉文件扩展名），外挂/格式/语言用胶囊标签；
/// 移除按钮（垃圾桶）单独放最右。
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
        selected
            ? Icons.closed_caption_rounded
            : Icons.closed_caption_outlined,
        color: selected ? accent : Colors.white54,
        size: 22,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _trackTitle(track),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : Colors.white,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (track.external) const _TrackTag('外挂'),
          if (track.codec != null && track.codec!.trim().isNotEmpty)
            _TrackTag(track.codec!.trim().toUpperCase()),
          if (track.language != null &&
              track.language!.trim().isNotEmpty &&
              track.language!.trim() != track.displayTitle)
            _TrackTag(track.language!.trim()),
        ],
      ),
      trailing: onRemove != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 20),
              tooltip: '移除已导入的字幕',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
            )
          : null,
      onTap: onTap,
    );
  }
}

/// 轨道标题：外挂字幕的 title 通常是文件名，去掉扩展名（如 `xxx.ass` → `xxx`）。
String _trackTitle(SubtitleTrack track) {
  final t = track.displayTitle;
  if (track.external && isSupportedSubtitleFile(t)) {
    return t.substring(0, t.lastIndexOf('.'));
  }
  return t;
}

/// 轨道信息胶囊标签（外挂 / 格式 / 语言）。
class _TrackTag extends StatelessWidget {
  final String text;

  const _TrackTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      ),
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
  final VoidCallback onTap;

  const _SubtitleSettingsEntry({
    required this.icon,
    required this.label,
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
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final bool displayCapsule;

  const _SettingSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onReset,
    this.displayCapsule = false,
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
              if (displayCapsule)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    display,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else
                Text(
                  display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (onReset != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onReset,
                  child: const Text(
                    '重置',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: _panelSliderTheme(),
            child: Slider(
              min: min,
              max: max,
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
            const SizedBox(height: 18),
            const _SectionLabel('快捷调整'),
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
        final hasBorder = settings.borderColor != null;
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
                    presetColors: SubtitlePresetColor.textPresets,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setColor(v ?? '#FFFFFF')),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _ColorEditorRow(
                    label: '描边颜色',
                    value: settings.borderColor,
                    allowNone: true,
                    defaultColor: const (r: 0, g: 0, b: 0, a: 255),
                    presetColors: SubtitlePresetColor.borderPresets,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setBorderColor(v)),
                  ),
                  // 描边粗细：紧跟描边颜色（设置了描边颜色时才显示）
                  if (hasBorder)
                    _SettingSlider(
                      label: '描边粗细',
                      display: settings.borderSize.toStringAsFixed(1),
                      value: settings.borderSize,
                      min: 0,
                      max: 10,
                      onChanged: (v) {
                        settings.setBorderSize(v);
                        controller.applyAllSettings();
                      },
                      onReset: () {
                        settings.setBorderSize(2.5);
                        controller.applyAllSettings();
                      },
                      displayCapsule: true,
                    ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
                  _ColorEditorRow(
                    label: '背景颜色',
                    value: settings.backColor,
                    allowNone: true,
                    defaultColor: const (r: 0, g: 0, b: 0, a: 128),
                    presetColors: SubtitlePresetColor.backPresets,
                    onSelect: (c) =>
                        _apply(c, settings, (v) => settings.setBackColor(v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 文字效果 ─────────────────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('文字效果'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Row(
                      children: [
                        _LabelSwitch(
                          label: '粗体',
                          value: settings.bold,
                          onChanged: (v) {
                            settings.setBold(v);
                            controller.applyAllSettings();
                          },
                        ),
                        const SizedBox(width: 28),
                        _LabelSwitch(
                          label: '斜体',
                          value: settings.italic,
                          onChanged: (v) {
                            settings.setItalic(v);
                            controller.applyAllSettings();
                          },
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
                  // 只有切换 override 才需要重建轨道（sub-reload），
                  // 避免把重载混进高频的样式拖动路径导致卡顿。
                  // force 显式传目标值：setOverrideEmbeddedStyle 是异步的，
                  // 若不显式传，applyStyleOverride 会读到旧的 override 值。
                  controller.applyStyleOverride(force: v);
                },
              ),
            ),
            const SizedBox(height: 12),
            // ── 不生效提示（精炼文案）───────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4A3A13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6B5618)),
              ),
              child: const Text(
                '若样式调整无效果，可能为ASS字幕，需要启用强制字幕覆盖即可生效',
                style: TextStyle(color: Color(0xFFFFE082), fontSize: 12, height: 1.4),
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
}

/// 把 mpv 颜色串（`#RRGGBB` / `#AARRGGBB`，8 位时 alpha 在前）转成 Flutter
/// [Color]（同样为 ARGB）。
Color colorFromMpvHex(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 8) {
    final val = int.tryParse(h, radix: 16);
    return val != null ? Color(val) : Colors.white;
  }
  if (h.length == 6) {
    final val = int.tryParse(h, radix: 16);
    return val != null ? Color(0xFF000000 | val) : Colors.white;
  }
  return Colors.white;
}

/// 单个颜色的编辑行：标题 + 预设色点 + 第二/三行全宽「自定义」展开 RGBA 滑杆。
class _ColorEditorRow extends StatefulWidget {
  final String label;
  final String? value;
  final bool allowNone;
  final SubtitleRgba defaultColor;
  final List<SubtitlePresetColor> presetColors;
  final ValueChanged<String?> onSelect;

  const _ColorEditorRow({
    required this.label,
    required this.value,
    this.allowNone = false,
    this.defaultColor = const (r: 255, g: 255, b: 255, a: 255),
    this.presetColors = SubtitlePresetColor.textPresets,
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
        : widget.defaultColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 颜色预览点
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
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
                    ? const Icon(Icons.block, size: 12, color: Colors.white70)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 预设色胶囊（一行或两行排布）
        _buildPresets(),
        const SizedBox(height: 8),
        // 下方独立一行全宽「自定义」胶囊（与预设胶囊总宽度一致）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => setState(() => _custom = !_custom),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _custom
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _custom ? _accent : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _custom ? '收起自定义调色' : '自定义调色',
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
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 展开的 RGBA 四通道滑杆
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _custom ? _buildChannels(base) : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 预设色胶囊（多行自适应等宽）
  Widget _buildPresets() {
    final allItems = <({String? hex, String label})>[
      if (widget.allowNone) (hex: null, label: '无'),
      for (final c in widget.presetColors) (hex: c.hex, label: c.label),
    ];

    // 一行最多 4 项，超过则 3 + 剩余 换行。
    // 不再额外加「当前」胶囊——当前色已由左上角预览点体现。
    final List<List<({String? hex, String label})>> rows = allItems.length <= 4
        ? [allItems]
        : [allItems.sublist(0, 3), allItems.sublist(3)];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var j = 0; j < rows[i].length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ColorDot(
                      hex: rows[i][j].hex,
                      label: rows[i][j].label,
                      selected: rows[i][j].hex == null
                          ? widget.value == null
                          : _matchesPreset(rows[i][j].hex!),
                      onTap: () => widget.onSelect(rows[i][j].hex),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _matchesPreset(String hex) {
    if (widget.value == null) return false;
    final a = mpvColorToRgba(widget.value!);
    final b = mpvColorToRgba(hex);
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
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

/// 预设色胶囊（圆形色块 + 名称，选中带勾）
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
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: hex == null ? Colors.black26 : colorFromMpvHex(hex!),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex == null ? Colors.white24 : Colors.white38,
                  width: 0.5,
                ),
              ),
              child: hex == null
                  ? const Icon(Icons.block, size: 9, color: Colors.white70)
                  : (selected
                      ? const Icon(Icons.check, size: 9, color: Colors.black54)
                      : null),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
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

/// 紧凑的文字效果开关：标签紧跟开关（区别于 SwitchListTile 的左右分离布局）。
class _LabelSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LabelSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(width: 6),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    onChanged: (v) {
                      settings.setPosition(v);
                      controller.applyAllSettings();
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: TextButton.icon(
                        onPressed: () async {
                          await settings.setScale(1.0);
                          await settings.setPosition(100);
                          await controller.applyAllSettings();
                        },
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('重置缩放与位置'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
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

/// 字幕字体二级页：先强制选择一个「字体目录」（SAF 目录选择器），把目录里
/// 所有 .ttf/.otf/.ttc/.otc 一次性拷贝到应用私有 fonts/，再在字体列表里点击
/// 选择（含「默认字体」）；可刷新重新拷贝、可 ✕ 清除目录重选。
///
/// 不选目录时自定义字体列表为空、无法使用自定义字体（工作.md 第 1 点：
/// 强制性）。自定义字体通过 media_kit 的 `libassAndroidFontsDir` 在 Player
/// 构造时注入（mpv_initialize 前），换字体需退出播放器重新进入生效
/// （libass 机制，与小喵 player 一致）。
class SubtitleFontPanel extends StatefulWidget {
  final SubtitleController controller;

  const SubtitleFontPanel({super.key, required this.controller});

  @override
  State<SubtitleFontPanel> createState() => _SubtitleFontPanelState();
}

class _SubtitleFontPanelState extends State<SubtitleFontPanel> {
  List<SubtitleFontEntry> _entries = const [];
  String _fontsDir = '';
  bool _loading = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _fontsDir = SubtitleSettings.instance.fontsDir;
    _reloadEntries();
  }

  /// 重新扫描私有 fonts/ 目录，刷新字体列表（进入面板/导入/刷新后调用）。
  Future<void> _reloadEntries() async {
    final entries = await DeviceServices.listFontEntries();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// 选择字体目录 → 一次性拷贝全部字体 → 列出可选字体。
  Future<void> _pickDirectory() async {
    final uri = await DeviceServices.openFontDirectoryPicker();
    if (uri == null || !mounted) return;
    setState(() => _loading = true);
    await SubtitleSettings.instance.setFontSourceDir(uri);
    final dir = await DeviceServices.getFontsDirectory();
    final count = await DeviceServices.copyFontsFromDirectory(uri);
    final entries = await DeviceServices.listFontEntries();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fontsDir = dir;
      _entries = entries;
    });
    _showMessage('已导入 $count 个字体文件，共 ${entries.length} 种字体');
  }

  /// 刷新：从已记录的字体目录重新拷贝（目录里新增字体后点此）。
  Future<void> _refresh() async {
    final uri = SubtitleSettings.instance.fontSourceDir;
    if (uri.isEmpty) return;
    setState(() => _loading = true);
    await DeviceServices.copyFontsFromDirectory(uri);
    final entries = await DeviceServices.listFontEntries();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = entries;
    });
    _showMessage('已刷新，共 ${entries.length} 种字体');
  }

  /// 清除：清空私有 fonts/ + 忘记源目录 + 回退默认字体。
  Future<void> _clear() async {
    await DeviceServices.clearFontsDirectory();
    await SubtitleSettings.instance.setFontSourceDir('');
    await SubtitleSettings.instance.setFont('auto', '');
    if (!mounted) return;
    setState(() {
      _entries = const [];
      _fontsDir = '';
      _expanded = false;
    });
    _showMessage('已清除字体目录');
  }

  Future<void> _selectFont(SubtitleFontEntry entry) async {
    var dir = _fontsDir;
    if (dir.isEmpty) dir = await DeviceServices.getFontsDirectory();
    await SubtitleSettings.instance.setFont(entry.family, dir);
    if (!mounted) return;
    setState(() => _expanded = false);
    _showRestartHint();
  }

  Future<void> _selectDefault() async {
    await SubtitleSettings.instance.setFont('auto', '');
    if (!mounted) return;
    setState(() => _expanded = false);
    _showRestartHint();
  }

  void _showRestartHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('字体更改需退出播放器并重新进入后生效'),
          duration: Duration(milliseconds: 2000),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 2000),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final hasCustom = settings.font != 'auto';
        final hasSource = settings.fontSourceDir.isNotEmpty;
        return ListView(
          key: const PageStorageKey('subtitle_font'),
          padding: const EdgeInsets.all(16),
          children: [
            // ── 字体目录选择 ─────────────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('字体目录'),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_open,
                        color: Colors.white, size: 22),
                    title: const Text(
                      '选择字体目录',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    subtitle: Text(
                      _loading
                          ? '正在加载...'
                          : (hasSource
                              ? '已加载 ${_entries.length} 种字体'
                              : '点击选择包含 .ttf/.otf 字体的目录'),
                      style: TextStyle(
                        color: _entries.isNotEmpty
                            ? const Color(0xFF81C784)
                            : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    trailing: hasSource
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.refresh,
                                    color: Color(0xFF64B5F6), size: 22),
                                tooltip: '刷新',
                                visualDensity: VisualDensity.compact,
                                onPressed: _loading ? null : _refresh,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Color(0xFFEF5350), size: 22),
                                tooltip: '清除目录',
                                visualDensity: VisualDensity.compact,
                                onPressed: _loading ? null : _clear,
                              ),
                            ],
                          )
                        : const Icon(Icons.chevron_right,
                            color: Colors.white54),
                    onTap: () => _pickDirectory(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 当前字体 + 选择列表 ─────────────────
            _PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardLabel('当前字体'),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.text_fields,
                        color: Colors.white, size: 22),
                    title: Text(
                      hasCustom ? settings.font : '默认字体',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                    ),
                    trailing: _entries.isNotEmpty
                        ? Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.white54,
                          )
                        : const Text(
                            '请先选择字体目录',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                    onTap: _entries.isNotEmpty
                        ? () => setState(() => _expanded = !_expanded)
                        : null,
                  ),
                  if (_expanded) ...[
                    const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.white12),
                    _FontOptionTile(
                      label: '默认字体',
                      subtitle: '跟随系统字库',
                      selected: !hasCustom,
                      onTap: _selectDefault,
                    ),
                    for (final e in _entries)
                      _FontOptionTile(
                        label: e.family,
                        subtitle: e.file,
                        selected: settings.font == e.family,
                        onTap: () => _selectFont(e),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4A3A13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6B5618)),
              ),
              child: const Text(
                '字体更改需退出播放器并重新进入后生效；内嵌 ASS 字幕需开启「强制覆盖内嵌样式」后字体设置才会生效。',
                style: TextStyle(
                    color: Color(0xFFFFE082), fontSize: 12, height: 1.4),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 字体选项行（默认字体 / 自定义字体，单选高亮）。
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
    return ListTile(
      dense: true,
      leading: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _accent : Colors.white24,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 13, color: Colors.black87)
            : null,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? _accent : Colors.white,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
      onTap: onTap,
    );
  }
}