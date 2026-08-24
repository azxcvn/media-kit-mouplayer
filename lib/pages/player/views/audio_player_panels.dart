import 'package:flutter/material.dart';
import 'package:moumou/models/video_file.dart';

/// 听视频界面底部面板（工作.md 阶段1 第 2 点重设计）：
///
/// 倍速面板与播放列表面板统一为**深色胶囊风格**，与听视频界面沉浸式暗色一体；
/// 两个面板都带右上角「关闭」按钮（旧版倍速有关闭、列表没有的不一致已修复）。
///
/// - [showAudioSpeedSheet]：倍速档位胶囊 + 「定时关闭」预设胶囊；
/// - [showAudioPlaylistSheet]：播放列表（当前项高亮 + 等化器动画）+ 随机/循环胶囊。
///
/// 面板内数据全部由听视频页传入并通过回调写回，面板自身无状态。

/// 听视频强调色（与页面一致）
const Color kAudioAccent = Color(0xFF64B5F6);

/// 面板深色背景
const Color kAudioPanelBg = Color(0xFF1C1C24);

/// 听视频循环模式：关闭 → 单曲循环 → 列表循环（点击循环按钮三态切换）
enum AudioRepeatMode {
  off('循环关闭', Icons.repeat_rounded),
  single('单曲循环', Icons.repeat_one_rounded),
  loopAll('列表循环', Icons.repeat_rounded);

  final String label;
  final IconData icon;
  const AudioRepeatMode(this.label, this.icon);

  /// 三态循环：off → single → loopAll → off
  AudioRepeatMode get next => switch (this) {
        AudioRepeatMode.off => AudioRepeatMode.single,
        AudioRepeatMode.single => AudioRepeatMode.loopAll,
        AudioRepeatMode.loopAll => AudioRepeatMode.off,
      };
}

/// 定时关闭预设：关闭 / 15 分钟 / 30 分钟 / 60 分钟 / 自定义 / 播完当前曲目
enum AudioSleepPreset {
  off('关闭', Duration.zero),
  min15('15 分钟', Duration(minutes: 15)),
  min30('30 分钟', Duration(minutes: 30)),
  min60('60 分钟', Duration(minutes: 60)),
  custom('自定义', Duration.zero),
  trackEnd('播完当前', Duration.zero);

  final String label;
  final Duration duration;
  const AudioSleepPreset(this.label, this.duration);
}

// ────────────────────────────────────────────────────────────
// 倍速面板
// ────────────────────────────────────────────────────────────

/// 倍速面板：倍速档位胶囊 + 定时关闭预设胶囊（含自定义时长），右上角关闭按钮。
Future<void> showAudioSpeedSheet(
  BuildContext context, {
  required double speed,
  required List<double> options,
  required ValueChanged<double> onSpeed,
  required AudioSleepPreset sleepPreset,
  required void Function(AudioSleepPreset preset, {Duration? custom}) onSleepPreset,
  Duration sleepRemaining = Duration.zero,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kAudioPanelBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AudioPanelHeader(
              title: '播放速度',
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in options)
                  _AudioChip(
                    label: '${s.toStringAsFixed(1)}x',
                    selected: (s - speed).abs() < 0.001,
                    onTap: () {
                      onSpeed(s);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _AudioSectionLabel('定时关闭'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final p in AudioSleepPreset.values)
                  _AudioChip(
                    label: p.label,
                    selected: sleepPreset == p,
                    onTap: () async {
                      if (p == AudioSleepPreset.custom) {
                        final minutes = await _showCustomSleepDialog(
                          sheetContext,
                        );
                        if (minutes == null) return;
                        onSleepPreset(
                          AudioSleepPreset.custom,
                          custom: Duration(minutes: minutes),
                        );
                      } else {
                        onSleepPreset(p);
                      }
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
              ],
            ),
            // 定时关闭激活时显示剩余时间
            if (sleepPreset != AudioSleepPreset.off) ...[
              const SizedBox(height: 12),
              Text(
                sleepPreset == AudioSleepPreset.trackEnd
                    ? '将在当前曲目播放结束后停止'
                    : '剩余 ${_fmtDuration(sleepRemaining)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────
// 播放列表面板
// ────────────────────────────────────────────────────────────

/// 播放列表面板：曲目列表（当前项高亮）+ 随机/循环胶囊，右上角关闭按钮。
Future<void> showAudioPlaylistSheet(
  BuildContext context, {
  required List<VideoFile> videos,
  required int currentIndex,
  required bool shuffle,
  required AudioRepeatMode repeatMode,
  required ValueChanged<int> onSelect,
  required VoidCallback onToggleShuffle,
  required VoidCallback onCycleRepeat,
}) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  final sheetHeight =
      (MediaQuery.sizeOf(context).height * 0.6 - bottomInset)
          .clamp(280.0, double.infinity);
  // 面板内本地状态：随机/循环的展示值随点击即时更新，同时回调写回页面逻辑状态。
  var localShuffle = shuffle;
  var localRepeat = repeatMode;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kAudioPanelBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _AudioPanelHeader(
                  title: '播放列表（${videos.length}）',
                  onClose: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: videos.length,
                  itemBuilder: (context, i) {
                    final cur = i == currentIndex;
                    final v = videos[i];
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: cur
                          ? const _EqualizerBars(color: kAudioAccent)
                          : const SizedBox(width: 14, height: 14),
                      title: Text(
                        v.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cur
                              ? kAudioAccent
                              : Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight:
                              cur ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onSelect(i);
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              // 底部：随机播放 / 循环模式（胶囊）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AudioChip(
                      label: '随机播放',
                      icon: Icons.shuffle_rounded,
                      selected: localShuffle,
                      onTap: () {
                        localShuffle = !localShuffle;
                        onToggleShuffle();
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(width: 12),
                    _AudioChip(
                      label: localRepeat.label,
                      icon: localRepeat.icon,
                      selected: localRepeat != AudioRepeatMode.off,
                      onTap: () {
                        localRepeat = localRepeat.next;
                        onCycleRepeat();
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────
// 公共小组件
// ────────────────────────────────────────────────────────────

/// 面板标题行：左侧标题 + 右侧关闭按钮（两个面板统一，工作.md 阶段1 第 2 点）
class _AudioPanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _AudioPanelHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
          tooltip: '关闭',
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// 面板小节标题（如「定时关闭」）
class _AudioSectionLabel extends StatelessWidget {
  final String text;

  const _AudioSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// 深色胶囊选项：选中强调色填充，未选中半透明白底；可选前置图标。
class _AudioChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _AudioChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? kAudioAccent
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? kAudioAccent
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? Colors.black : Colors.white70),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前播放项的等化器跳动动画（三根竖条错相起伏）
class _EqualizerBars extends StatefulWidget {
  final Color color;

  const _EqualizerBars({required this.color});

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 3,
                  height: 4 + 10 * _barFactor(t, i),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _barFactor(double t, int index) {
    final phase = (t + index / 3) % 1.0;
    return 0.35 + 0.65 * (1 - _cos2pi(phase * 2)) / 2;
  }

  static double _cos2pi(double x) {
    final xx = x - x.roundToDouble();
    return 1 - 2 * xx * xx * (3 - 2 * xx.abs());
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 自定义定时关闭弹窗：滑杆选分钟（5 – 180，步进 5），确定返回分钟数。
Future<int?> _showCustomSleepDialog(BuildContext context) {
  int minutes = 30;
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF23232C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '自定义定时关闭',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$minutes 分钟',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: kAudioAccent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                thumbColor: kAudioAccent,
                trackHeight: 3,
              ),
              child: Slider(
                value: minutes.toDouble().clamp(5, 180),
                min: 5,
                max: 180,
                divisions: 35,
                onChanged: (v) => setDialogState(() => minutes = v.round()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(minutes),
            child: const Text('确定', style: TextStyle(color: kAudioAccent)),
          ),
        ],
      ),
    ),
  );
}
