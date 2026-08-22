import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 播放器设置子页：双击手势、快进/快退时长（固定档位 + 点数值原地自定义）、
/// 音量/亮度手势灵敏度、长按倍速（倍率滑杆，归「手势」组）、
/// 自动连播 / 播放完毕自动退出（归「播放行为」组）、
/// 常驻进度线、倍速记忆、按钮背景、双指缩放、已观看进度阈值。
///
/// 分组结构（各组别内的设置项以分割线分隔）：
/// - **手势**：双击手势、快进/快退时长、音量/亮度灵敏度、长按倍速滑杆
///   （工作.md 第 3 点：全部归为**一张卡片**内，项间用分割线分隔）；
/// - **视频方向**：自动 / 锁定竖屏 / 锁定横屏（工作.md 第 5 点）；
/// - **播放行为**：常驻进度线、进度条缩略图、记住上次倍速、保存音量到系统、
///   双指缩小视频、按钮背景、自动连播、播放完毕自动退出、倍速播放指示器、
///   启用播放界面动画（工作.md 第 7 点）；
/// - **已观看进度阈值**：滑杆设置（5% – 100%，步进 5%）。
///
/// 循环播放模式（关闭/列表循环/单集循环）已移至播放界面内调整
/// （顶栏/更多面板的「循环播放」槽位动作），本页不再提供。
/// 超分辨率（模式/质量/记忆）在播放界面右下角入口直接调整，本页不提供；
/// 控制栏（启用动作）的编辑只在播放器内进行（「更多 → 编辑控制栏」），本页不提供。
class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  IconData _modeIcon(DoubleTapMode mode) {
    return switch (mode) {
      DoubleTapMode.pause => Icons.pause_circle_outline,
      DoubleTapMode.seek => Icons.fast_forward_outlined,
      DoubleTapMode.mixed => Icons.touch_app_outlined,
    };
  }

  IconData _orientationIcon(VideoOrientationMode mode) {
    return switch (mode) {
      VideoOrientationMode.auto => Icons.smartphone,
      VideoOrientationMode.portrait => Icons.screen_lock_portrait,
      VideoOrientationMode.landscape => Icons.screen_lock_landscape,
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
              // ── 手势（工作.md 第 3 点：所有手势设置归为一张卡片）──
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
                    // 快进/快退时长（双击手势与中央按钮共用）
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _SeekSettingTile(
                      value: settings.seekSeconds,
                      onChanged: settings.setSeekSeconds,
                    ),
                    // 音量/亮度灵敏度
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _SensitivityTile(
                      icon: Icons.volume_up_outlined,
                      title: '音量灵敏度',
                      value: settings.volumeSensitivity,
                      onChanged: settings.setVolumeSensitivity,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _SensitivityTile(
                      icon: Icons.brightness_6_outlined,
                      title: '亮度灵敏度',
                      value: settings.brightnessSensitivity,
                      onChanged: settings.setBrightnessSensitivity,
                    ),
                    // 长按倍速滑杆（归入手势组别）
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _LongPressSpeedTile(
                      value: settings.longPressSpeed,
                      onChanged: settings.setLongPressSpeed,
                    ),
                  ],
                ),
              ),
              // ── 视频方向（工作.md 第 5 点）────────────────
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '视频方向'),
              SettingsCard(
                child: Column(
                  children: [
                    for (final m in VideoOrientationMode.values)
                      SettingsRadioTile(
                        icon: _orientationIcon(m),
                        title: m.label,
                        subtitle: switch (m) {
                          VideoOrientationMode.auto => const Text('按视频方向自动横屏或竖屏播放'),
                          VideoOrientationMode.portrait =>
                            const Text('无论视频方向，统一竖屏播放'),
                          VideoOrientationMode.landscape =>
                            const Text('无论视频方向，统一横屏播放'),
                        },
                        selected: settings.videoOrientation == m,
                        onTap: () => settings.setVideoOrientation(m),
                      ),
                  ],
                ),
              ),
              // ── 顶部信息（工作.md 第 12 点）──────────────
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '顶部信息'),
              SettingsCard(
                child: Column(
                  children: [
                    for (final m in TopStatusDisplay.values)
                      SettingsRadioTile(
                        icon: switch (m) {
                          TopStatusDisplay.off => Icons.visibility_off_outlined,
                          TopStatusDisplay.time => Icons.access_time,
                          TopStatusDisplay.battery => Icons.battery_full,
                          TopStatusDisplay.both =>
                            Icons.schedule_send_outlined,
                        },
                        title: m.label,
                        subtitle: Text(switch (m) {
                          TopStatusDisplay.off => '不显示时间与电量，不占用顶部区域',
                          _ => '在播放界面顶部居中显示时间与电量',
                        }),
                        selected: settings.topStatusDisplay == m,
                        onTap: () => settings.setTopStatusDisplay(m),
                      ),
                  ],
                ),
              ),
              // ── 播放行为（原「播放」组别改名）────────────
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '播放行为'),
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
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.image_outlined,
                      title: '进度条缩略图',
                      subtitle: const Text('拖动进度条时预览画面；默认关闭，开启后仅在拖动时后台预热'),
                      trailing: Switch(
                        value: settings.showThumbnailPreview,
                        onChanged: (v) => settings.setShowThumbnailPreview(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.speed,
                      title: '记住上次倍速',
                      subtitle: const Text('下次打开视频自动恢复上次的播放速度'),
                      trailing: Switch(
                        value: settings.rememberSpeed,
                        onChanged: (v) => settings.setRememberSpeed(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.volume_off_outlined,
                      title: '保存音量到系统',
                      subtitle: const Text('退出播放时将本次调整的音量写回系统；关闭则恢复进入前音量'),
                      trailing: Switch(
                        value: settings.saveVolumeToSystem,
                        onChanged: (v) => settings.setSaveVolumeToSystem(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.pinch_outlined,
                      title: '双指缩小视频',
                      subtitle: const Text('双指可缩放画面（最小 0.75 倍，最大 4 倍）；关闭则最小回到原始大小'),
                      trailing: Switch(
                        value: settings.enableShrinkVideo,
                        onChanged: (v) => settings.setEnableShrinkVideo(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.radio_button_checked,
                      title: '按钮背景',
                      subtitle: const Text('为播放控制按钮添加半透明圆角背景'),
                      trailing: Switch(
                        value: settings.showButtonBackground,
                        onChanged: (v) => settings.setShowButtonBackground(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.skip_next_rounded,
                      title: '自动连播',
                      subtitle: const Text('当前视频播完后自动播放下一集'),
                      trailing: Switch(
                        value: settings.autoNext,
                        onChanged: (v) => settings.setAutoNext(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.exit_to_app,
                      title: '播放完毕自动退出',
                      subtitle: const Text('当前文件夹最后一个视频播完后自动退出播放页'),
                      trailing: Switch(
                        value: settings.autoExit,
                        onChanged: (v) => settings.setAutoExit(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.speed_rounded,
                      title: '倍速播放指示器',
                      subtitle: const Text('长按时在屏幕顶部显示「正在 X.Xx 倍速播放」'),
                      trailing: Switch(
                        value: settings.showSpeedIndicator,
                        onChanged: (v) => settings.setShowSpeedIndicator(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.animation_outlined,
                      title: '启用播放界面动画',
                      subtitle: const Text('关闭后播放页控制层与各面板直接出现/消失，不再显示进出场动画'),
                      trailing: Switch(
                        value: settings.playerAnimations,
                        onChanged: (v) => settings.setPlayerAnimations(v),
                      ),
                    ),
                  ],
                ),
              ),
              // 已观看进度阈值（视频列表「进度」字段的完成判定）
              const SettingsGroupTitle(title: '已观看进度阈值'),
              SettingsCard(
                child: _WatchThresholdTile(
                  value: settings.watchThreshold,
                  onChanged: settings.setWatchThreshold,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 音量/亮度手势灵敏度设置项：图标 + 标题 + 右侧倍率数值 + 滑杆（0.5x – 2.0x）。
/// 灵敏度含义：满屏滑动对应的量程倍率（1.0 = 满屏滑完整个量程）。
class _SensitivityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  const _SensitivityTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)}x',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSecondaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: kazumiSliderTheme(scheme),
            child: Slider(
              min: PlayerControlsSettings.minGestureSensitivity,
              max: PlayerControlsSettings.maxGestureSensitivity,
              divisions: 15,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 长按倍速设置项（滑杆式，参考快进/快退时长调节样式）：
/// 图标 + 固定标题 + 右侧倍率数值 + 滑杆（1 – 6 倍，步进 0.1，离散）。
class _LongPressSpeedTile extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _LongPressSpeedTile({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '长按倍速',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)}x',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSecondaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 50 档刻度过密会被 Flutter 跳过绘制，用密集刻度形状保证有圆点
          SliderTheme(
            data: kazumiSliderTheme(scheme).copyWith(
              tickMarkShape: const DenseSliderTickMarkShape(),
            ),
            child: Slider(
              min: PlayerControlsSettings.minLongPressSpeed,
              max: PlayerControlsSettings.maxLongPressSpeed,
              divisions: 50,
              value: value,
              onChanged: onChanged,
            ),
          ),
          Text(
            '长按屏幕临时倍速播放（1 – 6 倍，步进 0.1）；长按期间左右滑动可在 1.5 – 4 倍间临时调速',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
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

/// 「已观看」进度阈值设置项（滑杆式，5% – 100%，步进 5%，默认 95%）：
/// 视频列表「进度」字段据此判定 未观看 / 观看中 / 已看完（看完的卡片置灰）。
class _WatchThresholdTile extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _WatchThresholdTile({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '「已观看」进度阈值',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSecondaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: kazumiSliderTheme(scheme).copyWith(
              tickMarkShape: const DenseSliderTickMarkShape(),
            ),
            child: Slider(
              min: PlayerControlsSettings.minWatchThreshold,
              max: PlayerControlsSettings.maxWatchThreshold,
              divisions: 19,
              value: value,
              onChanged: onChanged,
            ),
          ),
          Text(
            '播放进度达到该比例即视为「已看完」（列表置灰）。5% – 100%，步进 5%，默认 95%。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
