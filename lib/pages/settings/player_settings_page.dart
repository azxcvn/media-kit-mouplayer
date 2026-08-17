import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 播放器设置子页：双击手势、快进/快退时长（固定档位 + 点数值原地自定义）、
/// 常驻进度线、倍速记忆。
///
/// 控制栏（启用动作）的编辑只在播放器内进行（「更多 → 编辑控制栏」），
/// 本页不提供。
class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  IconData _modeIcon(DoubleTapMode mode) {
    return switch (mode) {
      DoubleTapMode.pause => Icons.pause_circle_outline,
      DoubleTapMode.seek => Icons.fast_forward_outlined,
      DoubleTapMode.mixed => Icons.touch_app_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = PlayerControlsSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('播放器设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              // ── 手势 ──────────────────────────────
              const SettingsGroupTitle(title: '手势'),
              SettingsCard(
                child: Column(
                  children: [
                    for (final m in DoubleTapMode.values)
                      SettingsRadioTile(
                        icon: _modeIcon(m),
                        title: m.label,
                        selected: settings.doubleTapMode == m,
                        onTap: () => settings.setDoubleTapMode(m),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 快进/快退时长（双击手势与中央按钮共用）
              SettingsCard(
                child: _SeekSettingTile(
                  value: settings.seekSeconds,
                  onChanged: settings.setSeekSeconds,
                ),
              ),
              // ── 播放 ──────────────────────────────
              const SettingsGroupTitle(title: '播放'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsTile(
                      icon: Icons.horizontal_rule,
                      title: '常驻进度线',
                      subtitle: const Text('隐藏控制层后，屏幕底部保留一条细进度线'),
                      trailing: Switch(
                        value: settings.showProgressLine,
                        onChanged: (v) => settings.setShowProgressLine(v),
                      ),
                    ),
                    SettingsTile(
                      icon: Icons.speed,
                      title: '记住上次倍速',
                      subtitle: const Text('下次打开视频自动恢复上次的播放速度'),
                      trailing: Switch(
                        value: settings.rememberSpeed,
                        onChanged: (v) => settings.setRememberSpeed(v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 快进/快退时长设置项（Kazumi 风格）：
/// 左侧图标 + 固定标题，右侧数值胶囊（点击原地变输入框，1 – 600 秒），
/// 下方固定档位滑杆（5/10/15/20/25/30 秒）。
class _SeekSettingTile extends StatefulWidget {
  static const _gears = [5, 10, 15, 20, 25, 30];

  final int value;
  final ValueChanged<int> onChanged;

  const _SeekSettingTile({required this.value, required this.onChanged});

  @override
  State<_SeekSettingTile> createState() => _SeekSettingTileState();
}

class _SeekSettingTileState extends State<_SeekSettingTile> {
  bool _editing = false;
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() {
    _controller.text = '${widget.value}';
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  void _commit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < 1 || v > PlayerControlsSettings.maxSeekSeconds) {
      setState(
        () => _error =
            '1 – ${PlayerControlsSettings.maxSeekSeconds} 秒',
      );
      return;
    }
    widget.onChanged(v);
    setState(() => _editing = false);
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 档位滑杆只覆盖 5–30，超出档位的手动值按边界显示，数值以右侧为准
    final sliderValue =
        widget.value.clamp(_SeekSettingTile._gears.first, _SeekSettingTile._gears.last).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fast_forward_rounded,
                  size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              // 固定标题：用户只可自定义秒数，不可改文本
              const Expanded(
                child: Text(
                  '快进/快退时长',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              // 数值：点击原地变输入框（1 – 600 秒）
              if (_editing)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      suffixText: '秒',
                      isDense: true,
                      errorText: _error,
                      errorStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _commit(),
                    onTapOutside: (_) => _cancel(),
                  ),
                )
              else
                GestureDetector(
                  onTap: _startEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.value} 秒',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 固定档位滑杆（Kazumi 风格：2024 新式、离散档位、无气泡）
          SliderTheme(
            data: kazumiSliderTheme(scheme),
            child: Slider(
              min: _SeekSettingTile._gears.first.toDouble(),
              max: _SeekSettingTile._gears.last.toDouble(),
              divisions: _SeekSettingTile._gears.length - 1,
              value: sliderValue,
              onChanged: (v) => widget.onChanged(v.round()),
            ),
          ),
          Text(
            '点击右侧数值可自定义 1 – ${PlayerControlsSettings.maxSeekSeconds} 秒',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
