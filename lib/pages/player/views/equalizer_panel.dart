import 'package:flutter/material.dart';
import 'package:moumou/models/equalizer_preset.dart';
import 'package:moumou/services/equalizer_settings.dart';

/// 音频均衡器面板：播放器内「更多 → 音频均衡器」右侧滑入 / 竖屏底部弹出。
///
/// 对齐小喵 player 的 `EqualizerDrawer` 设计：
/// - 顶部「启用均衡器」开关（同时门控频段 / 低音增强 / 虚拟环绕）；
/// - 内置预设（平直/古典/摇滚/流行/爵士/人声/低音/高音/舞曲/电子/蓝调/金属/嘻哈/R&B）；
/// - 5 段竖向滑块（60/230/910/3.6k/14k Hz，-15 ~ +15 dB，1dB 步进）；
/// - 低音增强（0-100）+ 虚拟环绕（0-100）横向滑块；
/// - 「一键重置」归零各项数值。
///
/// 状态来自全局持久化的 [EqualizerSettings.instance]；滑块拖动期间用本地
/// 状态跟随手指、松手才提交（避免拖动过程高频写 shared_preferences，
/// 对齐小喵 player 的 `onValueChangeFinished` 与小喵字幕字体滑块的提交纪律）。
class PlayerEqualizerPanel extends StatefulWidget {
  const PlayerEqualizerPanel({super.key});

  @override
  State<PlayerEqualizerPanel> createState() => _PlayerEqualizerPanelState();
}

class _PlayerEqualizerPanelState extends State<PlayerEqualizerPanel> {
  final EqualizerSettings _settings = EqualizerSettings.instance;

  // 拖动期间的本地镜像（松手提交到 _settings）
  late List<double> _bands;
  late double _bass;
  late double _virt;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _syncFromSettings();
    // 设置可能尚未 load（极端竞态），load 完成后回填一次
    _settings.ensureLoaded().then((_) {
      if (mounted) _syncFromSettings();
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // 拖动期间不反写本地值（避免手指还没松就被外部通知打断）
    if (mounted && !_dragging) _syncFromSettings();
  }

  void _syncFromSettings() {
    _bands = List.of(_settings.bands);
    _bass = _settings.bassBoost.toDouble();
    _virt = _settings.virtualizer.toDouble();
    if (mounted) setState(() {});
  }

  void _beginDrag() => _dragging = true;

  void _endDrag() {
    _dragging = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _settings.enabled;
    return ListView(
      key: const PageStorageKey('equalizer_main'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // ── 开关 ──────────────────────────────────────────
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '启用均衡器',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          subtitle: const Text(
            '调节频段增益、低音增强和虚拟环绕',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          value: enabled,
          onChanged: (v) => _settings.setEnabled(v),
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── 预设 ──────────────────────────────────────────
        const _SectionLabel('预设'),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: kEqualizerPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = kEqualizerPresets[i];
              final selected = _settings.presetId == p.id;
              return _PresetChip(
                label: p.label,
                selected: selected,
                enabled: enabled,
                onTap: () => _settings.applyPreset(p),
              );
            },
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── 5 段 ──────────────────────────────────────────
        const _SectionLabel('频段调节'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < kEqualizerBandCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _VerticalEqSlider(
                  value: _bands[i],
                  label: kEqualizerBandLabels[i],
                  enabled: enabled,
                  onChanged: (v) {
                    _beginDrag();
                    setState(() => _bands[i] = v);
                  },
                  onChangeEnd: (v) {
                    _bands[i] = v.roundToDouble();
                    _endDrag();
                    _settings.setBand(i, v);
                  },
                ),
              ),
            ],
          ],
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── 低音增强 ──────────────────────────────────────
        _BoostSlider(
          title: '低音增强',
          value: _bass,
          enabled: enabled,
          onChanged: (v) {
            _beginDrag();
            setState(() => _bass = v);
          },
          onChangeEnd: (v) {
            _bass = v.roundToDouble();
            _endDrag();
            _settings.setBassBoost(v.round());
          },
        ),
        const SizedBox(height: 4),
        // ── 虚拟环绕 ──────────────────────────────────────
        _BoostSlider(
          title: '虚拟环绕',
          value: _virt,
          enabled: enabled,
          onChanged: (v) {
            _beginDrag();
            setState(() => _virt = v);
          },
          onChangeEnd: (v) {
            _virt = v.roundToDouble();
            _endDrag();
            _settings.setVirtualizer(v.round());
          },
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── 重置 ──────────────────────────────────────────
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _settings.resetValues(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF4FC3F7),
          ),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('一键重置'),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 预设胶囊（横向滚动单选）。
class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF4FC3F7);
    final border = selected ? accent : Colors.white24;
    final fg = selected ? accent : (enabled ? Colors.white70 : Colors.white30);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
        ),
        child: Text(
          label,
          style: TextStyle(color: fg, fontSize: 13),
        ),
      ),
    );
  }
}

/// 单个竖向均衡器滑块（上正下负，中间是旋转 270° 的横向 Slider）。
class _VerticalEqSlider extends StatelessWidget {
  final double value;
  final String label;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VerticalEqSlider({
    required this.value,
    required this.label,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4FC3F7);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${value.round()}dB',
          style: TextStyle(
            color: enabled ? accent : Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 44,
          height: 150,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value
                  .clamp(kEqualizerMinBandDb, kEqualizerMaxBandDb)
                  .toDouble(),
              min: kEqualizerMinBandDb,
              max: kEqualizerMaxBandDb,
              divisions: 30,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

/// 低音增强 / 虚拟环绕共用的横向滑块（0-100，显示百分比）。
class _BoostSlider extends StatelessWidget {
  final String title;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BoostSlider({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4FC3F7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${value.round()}%',
              style: TextStyle(
                color: enabled ? accent : Colors.white30,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, 100).toDouble(),
          min: 0,
          max: 100,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
      ],
    );
  }
}
