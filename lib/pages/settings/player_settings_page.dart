import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/decode_settings.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/utils/app_dialog.dart';
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
    final decodeSettings = DecodeSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('播放设置')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, decodeSettings]),
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
                          VideoOrientationMode.auto => const Text('跟随视频方向'),
                          VideoOrientationMode.portrait =>
                            const Text('始终竖屏'),
                          VideoOrientationMode.landscape =>
                            const Text('始终横屏'),
                        },
                        selected: settings.videoOrientation == m,
                        onTap: () => settings.setVideoOrientation(m),
                      ),
                  ],
                ),
              ),
              // ── 顶部信息（工作.md 阶段1 第 1 点：时间/电量/网速/数据类型多选）──
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '顶部信息'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsCheckboxTile(
                      icon: Icons.access_time,
                      title: '时间',
                      subtitle: const Text('显示当前时间'),
                      checked: settings.showTopTime,
                      onChanged: settings.setShowTopTime,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsCheckboxTile(
                      icon: Icons.battery_full,
                      title: '电量',
                      subtitle: const Text('显示当前电量'),
                      checked: settings.showTopBattery,
                      onChanged: settings.setShowTopBattery,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsCheckboxTile(
                      icon: Icons.speed_outlined,
                      title: '网速',
                      subtitle: const Text('显示实时网速'),
                      checked: settings.showTopNetSpeed,
                      onChanged: settings.setShowTopNetSpeed,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsCheckboxTile(
                      icon: Icons.wifi_outlined,
                      title: '数据类型',
                      subtitle: const Text('显示 WiFi / 移动数据'),
                      checked: settings.showTopNetType,
                      onChanged: settings.setShowTopNetType,
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
                      subtitle: const Text('隐藏控制层后底部显示细线'),
                      trailing: Switch(
                        value: settings.showProgressLine,
                        onChanged: (v) => settings.setShowProgressLine(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.bookmarks_outlined,
                      title: '显示章节进度条',
                      subtitle: const Text('进度条标记章节并显示章节名'),
                      trailing: Switch(
                        value: settings.showChapterProgress,
                        onChanged: (v) => settings.setShowChapterProgress(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.image_outlined,
                      title: '进度条缩略图',
                      subtitle: const Text('拖动进度条时预览画面'),
                      trailing: Switch(
                        value: settings.showThumbnailPreview,
                        onChanged: (v) => settings.setShowThumbnailPreview(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.speed,
                      title: '记住上次倍速',
                      subtitle: const Text('自动恢复上次倍速'),
                      trailing: Switch(
                        value: settings.rememberSpeed,
                        onChanged: (v) => settings.setRememberSpeed(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.volume_off_outlined,
                      title: '保存音量到系统',
                      subtitle: const Text('退出时把音量写回系统'),
                      trailing: Switch(
                        value: settings.saveVolumeToSystem,
                        onChanged: (v) => settings.setSaveVolumeToSystem(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.pinch_outlined,
                      title: '双指缩小视频',
                      subtitle: const Text('双指缩放画面'),
                      trailing: Switch(
                        value: settings.enableShrinkVideo,
                        onChanged: (v) => settings.setEnableShrinkVideo(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.radio_button_checked,
                      title: '按钮背景',
                      subtitle: const Text('为控制按钮加半透明背景'),
                      trailing: Switch(
                        value: settings.showButtonBackground,
                        onChanged: (v) => settings.setShowButtonBackground(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.skip_next_rounded,
                      title: '自动连播',
                      subtitle: const Text('播完自动放下一集'),
                      trailing: Switch(
                        value: settings.autoNext,
                        onChanged: (v) => settings.setAutoNext(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.exit_to_app,
                      title: '播放完毕自动退出',
                      subtitle: const Text('最后一个播完自动退出'),
                      trailing: Switch(
                        value: settings.autoExit,
                        onChanged: (v) => settings.setAutoExit(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.speed_rounded,
                      title: '倍速播放指示器',
                      subtitle: const Text('长按时顶部显示倍速提示'),
                      trailing: Switch(
                        value: settings.showSpeedIndicator,
                        onChanged: (v) => settings.setShowSpeedIndicator(v),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsTile(
                      icon: Icons.animation_outlined,
                      title: '启用播放界面动画',
                      subtitle: const Text('控制层与面板的进出场动画'),
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
              // ── 解码（GPU-next / Vulkan 可选渲染后端，重启播放器生效）──
              const SizedBox(height: 16),
              const SettingsGroupTitle(title: '解码'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.auto_awesome_outlined,
                      title: '启用 GPU-next',
                      subtitle: const Text('使用 libplacebo 新渲染器'),
                      value: decodeSettings.gpuNext,
                      onChanged: (v) => _onGpuNextChanged(context, v),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SettingsSwitchTile(
                      icon: Icons.memory_outlined,
                      title: '启用 Vulkan',
                      subtitle: const Text('改用 Vulkan 渲染后端'),
                      value: decodeSettings.useVulkan,
                      onChanged: decodeSettings.gpuNext
                          ? (v) => _onVulkanChanged(context, v)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '切换后需重启播放器（重开视频）生效；Vulkan 需设备支持，不支持时自动回退 OpenGL',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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

  /// 启用 GPU-next 前的二次确认：超分不可用 + 杜比视界提示。
  /// 仅开启时弹窗（关闭直接生效）；取消则不写设置。
  Future<void> _onGpuNextChanged(BuildContext context, bool v) async {
    if (!v) {
      DecodeSettings.instance.setGpuNext(false);
      return;
    }
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('启用 GPU-next'),
        content: const Text(
          '启用后超分辨率功能将无法使用；\n可尝试配合软解播放杜比视界视频。\n\n是否继续？',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定启用'),
          ),
        ],
      ),
    );
    if (ok == true) DecodeSettings.instance.setGpuNext(true);
  }

  /// 启用 Vulkan 前的二次确认：告知可能的花屏/黑屏/崩溃与自动回退。
  /// 仅开启时弹窗（关闭直接生效）；取消则不写设置。
  Future<void> _onVulkanChanged(BuildContext context, bool v) async {
    if (!v) {
      DecodeSettings.instance.setVulkan(false);
      return;
    }
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('启用 Vulkan'),
        content: const Text(
          'Vulkan 需设备与驱动支持，部分设备可能出现花屏、黑屏或崩溃；\n不支持时自动回退 OpenGL。\n\n是否继续？',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定启用'),
          ),
        ],
      ),
    );
    if (ok == true) DecodeSettings.instance.setVulkan(true);
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
/// 图标 + 固定标题 + 右侧倍率数值 + 滑杆（1 – 4 倍，步进 0.5，离散）。
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
          // 1 – 4 倍、步进 0.5 共 7 档（(4-1)/0.5 = 6 个跨度）
          SliderTheme(
            data: kazumiSliderTheme(scheme).copyWith(
              tickMarkShape: const DenseSliderTickMarkShape(),
            ),
            child: Slider(
              min: PlayerControlsSettings.minLongPressSpeed,
              max: PlayerControlsSettings.maxLongPressSpeed,
              divisions: ((PlayerControlsSettings.maxLongPressSpeed -
                          PlayerControlsSettings.minLongPressSpeed) /
                      PlayerControlsSettings.longPressSpeedStep)
                  .round(),
              value: value,
              onChanged: onChanged,
            ),
          ),
          Text(
            '长按临时倍速，可左右滑动调速',
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
            '点击数值可自定义秒数',
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
            '进度达到该比例即视为已看完',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
