import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 倍速设置面板内容（通过 [showPlayerPanel] 弹出）。
///
/// 布局（自上而下）：
/// - 系统预设（0.5 – 4.0 间隔 0.5，点击立即生效并高亮）——第一眼就是预设；
/// - 我的预设（可删除，可整体重置）；
/// - 精确调速：Kazumi 风格滑杆（0.25 – 4.0 步进 0.05），只选值不生效；
/// - 大数字是滑杆读数（点击原地变输入框手动修改），由下方按钮决定去向；
/// - 「临时应用」为常亮开关：点击生效并高亮，再次点击取消恢复原速；
/// - 「重置预设」独占一行置于最下方，红色文字以区分。
class PlayerSpeedPanel extends StatefulWidget {
  /// 系统预设：0.5 – 4.0，间隔 0.5
  static List<double> get systemPresets =>
      [for (var i = 1; i <= 8; i++) i * 0.5];

  /// 当前实际倍速（可监听：面板打开期间外部切倍速会实时刷新 UI）
  final ValueNotifier<double> speedListenable;

  /// 应用倍速并写入记忆（点击预设/一键归位/取消临时应用时）
  final ValueChanged<double> onSpeedChanged;

  /// 临时应用倍速（不写入记忆）
  final ValueChanged<double> onTemporaryApply;

  /// 一键归位 1.0x
  final VoidCallback onReset;

  const PlayerSpeedPanel({
    super.key,
    required this.speedListenable,
    required this.onSpeedChanged,
    required this.onTemporaryApply,
    required this.onReset,
  });

  @override
  State<PlayerSpeedPanel> createState() => _PlayerSpeedPanelState();
}

class _PlayerSpeedPanelState extends State<PlayerSpeedPanel> {
  /// 候选倍速（滑杆/手动输入调整的目标值，应用后才成为实际倍速）
  late double _draft = widget.speedListenable.value;

  /// 临时应用是否生效（按钮常亮）
  bool _tempActive = false;

  /// 临时应用前的实际倍速（取消时恢复）
  double? _tempBase;

  /// 大数字是否处于原地输入态
  bool _editingDraft = false;
  final TextEditingController _draftController = TextEditingController();
  String? _draftError;

  @override
  void initState() {
    super.initState();
    // 面板是独立弹窗路由，播放页 setState 不会重建面板；
    // 通过监听实际倍速的变化实时刷新选中态与大数字（历史 bug：切倍速界面不刷新）
    widget.speedListenable.addListener(_handleSpeedChanged);
  }

  void _handleSpeedChanged() {
    if (!mounted) return;
    setState(() => _draft = widget.speedListenable.value);
  }

  @override
  void didUpdateWidget(covariant PlayerSpeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speedListenable != oldWidget.speedListenable) {
      oldWidget.speedListenable.removeListener(_handleSpeedChanged);
      widget.speedListenable.addListener(_handleSpeedChanged);
      _draft = widget.speedListenable.value;
    }
  }

  @override
  void dispose() {
    widget.speedListenable.removeListener(_handleSpeedChanged);
    _draftController.dispose();
    super.dispose();
  }

  /// 预设/归位：应用并记忆，同时退出临时应用态
  void _applyPreset(double p) {
    setState(() {
      _tempActive = false;
      _tempBase = null;
    });
    widget.onSpeedChanged(p);
  }

  /// 临时应用开关：点击生效（常亮），再点取消恢复原速
  void _toggleTemporary() {
    if (!_tempActive) {
      _tempBase = widget.speedListenable.value;
      widget.onTemporaryApply(_draft);
      setState(() => _tempActive = true);
    } else {
      widget.onSpeedChanged(_tempBase ?? widget.speedListenable.value);
      setState(() {
        _tempActive = false;
        _tempBase = null;
      });
    }
  }

  void _addToPresets() {
    final s = PlayerControlsSettings.instance;
    if (s.customSpeedPresets.any((e) => (e - _draft).abs() < 0.01)) {
      _toast('该倍速已在预设中');
      return;
    }
    if (s.customSpeedPresets.length >=
        PlayerControlsSettings.maxCustomSpeedPresets) {
      _toast('自定义预设已达上限（${PlayerControlsSettings.maxCustomSpeedPresets} 个）');
      return;
    }
    s.addCustomSpeedPreset(_draft);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── 大数字原地输入 ─────────────────────────────────────

  void _startEditDraft() {
    _draftController.text = _draft.toStringAsFixed(2);
    setState(() {
      _editingDraft = true;
      _draftError = null;
    });
  }

  void _commitDraft() {
    final v = double.tryParse(_draftController.text.trim());
    if (v == null ||
        v < PlayerControlsSettings.minSpeed ||
        v > PlayerControlsSettings.maxSpeed) {
      setState(
        () => _draftError =
            '${PlayerControlsSettings.minSpeed} – ${PlayerControlsSettings.maxSpeed}',
      );
      return;
    }
    setState(() {
      _draft = v;
      _editingDraft = false;
      _draftError = null;
    });
  }

  void _cancelEditDraft() {
    setState(() {
      _editingDraft = false;
      _draftError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = PlayerControlsSettings.instance;
    final scheme = Theme.of(context).colorScheme;
    final clamped = _draft.clamp(
      PlayerControlsSettings.minSpeed,
      PlayerControlsSettings.maxSpeed,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 系统预设（第一眼）──
          const _SectionLabel('预设'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in PlayerSpeedPanel.systemPresets)
                _SpeedChip(
                  label: formatSpeed(p),
                  selected: (widget.speedListenable.value - p).abs() < 0.001,
                  onTap: () => _applyPreset(p),
                ),
            ],
          ),
          // ── 我的预设 ──
          ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final customs = s.customSpeedPresets;
              if (customs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const _SectionLabel('我的预设'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in customs)
                        _CustomSpeedChip(
                          label: formatSpeed(p),
                          selected:
                              (widget.speedListenable.value - p).abs() < 0.001,
                          onTap: () => _applyPreset(p),
                          onRemove: () => s.removeCustomSpeedPreset(p),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // ── 精确调速（只选值，不生效）──
          const _SectionLabel('精确调速'),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                '0.25x',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: kazumiSliderTheme(scheme),
                  child: Slider(
                    min: PlayerControlsSettings.minSpeed,
                    max: PlayerControlsSettings.maxSpeed,
                    divisions: 75,
                    value: clamped,
                    // 只更新候选值，不改变实际播放速度
                    onChanged: (v) => setState(() => _draft = v),
                  ),
                ),
              ),
              const Text(
                '4x',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          // 大数字 = 滑杆读数；点击原地变输入框
          Center(
            child: _editingDraft
                ? SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _draftController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        suffixText: 'x',
                        suffixStyle: const TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                        ),
                        isDense: true,
                        errorText: _draftError,
                        errorStyle: const TextStyle(fontSize: 11),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onSubmitted: (_) => _commitDraft(),
                      onTapOutside: (_) => _cancelEditDraft(),
                    ),
                  )
                : GestureDetector(
                    onTap: _startEditDraft,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        formatSpeed(clamped),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          // ── 操作按钮 ──
          // 第一行三个胶囊（临时应用 / 添加到预设 / 归位）等宽排开，
          // 第二行「重置预设」等宽一行。用 Row+Expanded 结构性保证不换行，
          // 不使用 Wrap/IntrinsicWidth（其固有宽度计算不可靠，会挤到换行）。
          SizedBox(
            width: double.infinity,
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) {
                // 滑杆/输入值已是预设（系统或我的预设）时，「添加到预设」置灰
                final inPresets =
                    PlayerSpeedPanel.systemPresets.any(
                          (p) => (_draft - p).abs() < 0.01,
                        ) ||
                        s.customSpeedPresets.any(
                          (p) => (_draft - p).abs() < 0.01,
                        );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ActionPill(
                            label: '临时应用',
                            active: _tempActive,
                            onTap: _toggleTemporary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionPill(
                            label: '添加到预设',
                            enabled: !inPresets,
                            onTap: _addToPresets,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionPill(label: '归位', onTap: () {
                            setState(() => _draft = 1.0);
                            _applyPreset(1.0);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 重置预设：独占一行，红色文字
                    _DangerPill(
                      label: '重置预设',
                      onTap: s.resetCustomSpeedPresets,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 小节标题（预设 / 我的预设 / 精确调速）
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// 普通倍速胶囊（系统预设）：点击立即应用，选中态以主题色高亮
class _SpeedChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 内边距（自定义预设胶囊会传入更宽的右内边距，给删除角标留位）
  final EdgeInsets padding;

  const _SpeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

/// 自定义预设胶囊：右上角带删除角标
class _CustomSpeedChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _CustomSpeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 右内边距加宽（26），给删除角标留位，避免盖住倍速文本
        _SpeedChip(
          label: label,
          selected: selected,
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(14, 8, 26, 8),
        ),
        // 删除角标：小圆点（14）贴胶囊内部右上角，点击区 22x22 完全在胶囊内
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5484D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 9, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 操作按钮：临时应用为常亮开关（[active]），其余点击闪色反馈；
/// [enabled] 为 false 时置灰不可点（如「添加到预设」遇到已有倍速）。
class _ActionPill extends StatefulWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    this.active = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _flash = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active || _flash;
    // 禁用态：灰底灰字，不可点
    if (!widget.enabled) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? scheme.onPrimary : scheme.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 危险操作按钮（重置预设）：红色文字，独占一行，点击闪红反馈
class _DangerPill extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _DangerPill({required this.label, required this.onTap});

  @override
  State<_DangerPill> createState() => _DangerPillState();
}

class _DangerPillState extends State<_DangerPill> {
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 250), () {
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _flash
              ? scheme.error
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        // 撑满整行时文字居中（与上方三个按钮的总宽度对齐）
        child: Text(
          widget.label,
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
