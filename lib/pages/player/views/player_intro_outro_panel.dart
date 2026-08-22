import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 片头片尾设置面板内容（通过 [showPlayerPanel] 弹出）。
///
/// 参考小喵 player 的 SkipSettingsDrawer，布局（自上而下）：
/// - 全局开关：启用跳过片头片尾 + 副标题 + Switch（开启后展开下方内容）；
/// - 跳过片头段：标签 + 秒数输入（实时换算 mm:ss）+ 范围输入 +
///   0~范围滑杆 + 提示 + 「设为当前时间」按钮（强调色沿用章节
///   OP 片段橙 0xFFFF7A00）；
/// - 跳过片尾段：同款，按剩余时间计算，「设为当前剩余时间」
///   （强调色沿用章节 ED 片段粉 0xFFE05666）；
/// - 一键重置：秒数清零、范围回默认（红色胶囊，开关保持不变）。
///
/// 设置单例 [IntroOutroSettings] 变化时面板自动刷新（滑杆 / 读数 /
/// 输入框实时联动，无需重开面板）。
class PlayerIntroOutroPanel extends StatelessWidget {
  /// 当前播放位置（「设为当前时间」取数）
  final ValueListenable<Duration> positionListenable;

  /// 当前媒体时长（「设为当前剩余时间」取数）
  final ValueListenable<Duration> durationListenable;

  const PlayerIntroOutroPanel({
    super.key,
    required this.positionListenable,
    required this.durationListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: IntroOutroSettings.instance,
      builder: (context, _) {
        final s = IntroOutroSettings.instance;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildToggleRow(context, s),
              if (s.enabled) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 16),
                _SkipSection(
                  label: '跳过片头',
                  accent: ChapterSkipType.intro.color,
                  seconds: s.introSeconds,
                  range: s.introRange,
                  rangeLabel: '片头范围',
                  hint: '拖动或输入设置时间，可按需调整上方范围',
                  snapButtonText: '设为当前时间',
                  snapSeconds: () => positionListenable.value.inSeconds
                      .clamp(0, s.introRange),
                  onSecondsChanged: s.setIntroSeconds,
                  onRangeChanged: s.setIntroRange,
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Colors.white10),
                const SizedBox(height: 16),
                _SkipSection(
                  label: '跳过片尾',
                  accent: ChapterSkipType.outro.color,
                  seconds: s.outroSeconds,
                  range: s.outroRange,
                  rangeLabel: '片尾范围',
                  hint: '拖动或输入设置时间，可按需调整上方范围',
                  snapButtonText: '设为当前剩余时间',
                  snapSeconds: () {
                    final dur = durationListenable.value.inSeconds;
                    final pos = positionListenable.value.inSeconds;
                    return dur > pos ? (dur - pos).clamp(0, s.outroRange) : 0;
                  },
                  onSecondsChanged: s.setOutroSeconds,
                  onRangeChanged: s.setOutroRange,
                ),
                const SizedBox(height: 16),
                _ResetButton(onTap: () => s.reset()),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleRow(BuildContext context, IntroOutroSettings s) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '启用跳过片头片尾',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '通过手动设置秒数来跳过片头片尾',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.53),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: s.enabled, onChanged: (v) => s.setEnabled(v)),
      ],
    );
  }
}

/// 片头/片尾共用设置段：
/// 标签 + 秒数输入（实时换算 mm:ss）→ 范围输入 → 滑杆 → 提示 → 设为当前按钮。
class _SkipSection extends StatefulWidget {
  final String label;
  final Color accent;
  final int seconds;
  final int range;
  final String rangeLabel;
  final String hint;
  final String snapButtonText;

  /// 计算「设为当前」的目标秒数（片头 = 当前位置；片尾 = 剩余时间）
  final int Function() snapSeconds;
  final ValueChanged<int> onSecondsChanged;
  final ValueChanged<int> onRangeChanged;

  const _SkipSection({
    required this.label,
    required this.accent,
    required this.seconds,
    required this.range,
    required this.rangeLabel,
    required this.hint,
    required this.snapButtonText,
    required this.snapSeconds,
    required this.onSecondsChanged,
    required this.onRangeChanged,
  });

  @override
  State<_SkipSection> createState() => _SkipSectionState();
}

class _SkipSectionState extends State<_SkipSection> {
  final TextEditingController _secondsController = TextEditingController();
  final FocusNode _secondsFocus = FocusNode();
  final TextEditingController _rangeController = TextEditingController();
  final FocusNode _rangeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _secondsController.text = '${widget.seconds}';
    _rangeController.text = '${widget.range}';
  }

  @override
  void didUpdateWidget(covariant _SkipSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改值（滑杆/设为当前/一键重置）时同步输入框文本；
    // 正在输入时不覆盖（对齐 KT 的 hasUserEditedText）
    if (!_secondsFocus.hasFocus && oldWidget.seconds != widget.seconds) {
      _secondsController.text = '${widget.seconds}';
    }
    if (!_rangeFocus.hasFocus && oldWidget.range != widget.range) {
      _rangeController.text = '${widget.range}';
    }
  }

  @override
  void dispose() {
    _secondsController.dispose();
    _secondsFocus.dispose();
    _rangeController.dispose();
    _rangeFocus.dispose();
    super.dispose();
  }

  /// 输入过滤：只留数字；解析后钳制到 0 – range 并立即写设置
  void _handleSecondsInput(String raw) {
    final filtered = _digits(raw);
    if (filtered != raw) {
      _secondsController.text = filtered;
      _secondsController.selection =
          TextSelection.collapsed(offset: filtered.length);
    }
    final num = int.tryParse(filtered);
    if (num == null) return;
    widget.onSecondsChanged(num.clamp(0, widget.range));
  }

  /// 范围输入过滤：只留数字；解析后钳制到 10 – 600 并立即写设置
  void _handleRangeInput(String raw) {
    final filtered = _digits(raw);
    if (filtered != raw) {
      _rangeController.text = filtered;
      _rangeController.selection =
          TextSelection.collapsed(offset: filtered.length);
    }
    final num = int.tryParse(filtered);
    if (num == null) return;
    widget.onRangeChanged(num.clamp(
      IntroOutroSettings.minRangeSeconds,
      IntroOutroSettings.maxRangeSeconds,
    ));
  }

  String _digits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签 | 秒数输入 + 秒 + mm:ss 换算
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _NumberField(
              controller: _secondsController,
              focusNode: _secondsFocus,
              accent: widget.accent,
              fontSize: 15,
              onChanged: _handleSecondsInput,
            ),
            const SizedBox(width: 6),
            const Text('秒', style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                formatDuration(widget.seconds.clamp(0, widget.range) * 1000),
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 范围标签 | 范围输入 + s
        Row(
          children: [
            Expanded(
              child: Text(
                widget.rangeLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.73),
                  fontSize: 13,
                ),
              ),
            ),
            _NumberField(
              controller: _rangeController,
              focusNode: _rangeFocus,
              accent: widget.accent,
              fontSize: 13,
              onChanged: _handleRangeInput,
            ),
            const SizedBox(width: 4),
            const Text('s', style: TextStyle(color: Colors.white30, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        // 无级滑杆：0 – range，拖动实时写设置（秒数取整）
        SliderTheme(
          data: kazumiSliderTheme(scheme).copyWith(
            activeTrackColor: widget.accent,
            inactiveTrackColor: const Color(0xFF444444),
            thumbColor: widget.accent,
          ),
          child: Slider(
            min: 0,
            max: widget.range.toDouble(),
            value: widget.seconds
                .toDouble()
                .clamp(0, widget.range.toDouble()),
            onChanged: (v) => widget.onSecondsChanged(v.round()),
          ),
        ),
        Text(
          widget.hint,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.27),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        // 设为当前（描边胶囊，对齐 KT 的 snap 按钮）
        GestureDetector(
          onTap: () => widget.onSecondsChanged(widget.snapSeconds()),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.accent.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.snapButtonText,
              style: TextStyle(color: widget.accent, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// 数字输入框（暗底圆角，与 KT 的 BasicTextField 装饰一致）
class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final double fontSize;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.fontSize,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: fontSize, color: Colors.white),
        cursorColor: accent,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: const Color(0xFF1A2332),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// 一键重置（红色胶囊，对齐倍速面板的「重置预设」样式）
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
          '一键重置',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _flash ? scheme.onError : scheme.error,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
