import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/fast_thumbnails.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/utils/audio_shuffle.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/raw_thumb_image.dart';

/// 听视频界面（工作.md 第 10 点，参考小喵 KT 项目 AudioPlayerScreen）：
///
/// - 竖屏全屏独立界面，**共享横屏/竖屏播放页的同一个 [Player]**——
///   不新建播放器、不 open、不恢复进度（同一会话音频零中断）；
/// - 只播放音频不显示视频：整页被封面高斯模糊背景覆盖，画面完全隐藏，
///   退出后播放页从当前进度继续显示视频；
/// - 布局：顶栏（返回 + 「听视频」）+ 居中封面（16:9 圆角）+ 标题 +
///   进度条（拖动 seek）+ 底部控制卡（倍速 | 上一集 | 播放/暂停 | 下一集 |
///   播放列表）；
/// - 倍速范围 **0.5 – 3.0，步进 0.5**；倍速面板与播放列表面板**纯白背景**
///   从底部弹出（带进出场动画，showModalBottomSheet 自带）；
/// - 列表面板支持**随机播放**（时间刻算法 [audioShuffleNextIndex]）与
///   **列表循环**；
/// - 本界面内切歌**不恢复上次进度**（每首从 0 开始，像听歌一样）；
///   切走前保存原视频进度，退出界面后播放页从对应进度继续。
///
/// 由播放页「更多 → 听视频」push（竖屏），退出后由 push 方恢复横屏方向
/// 与沉浸式全屏。
class AudioPlayerPage extends StatefulWidget {
  /// 共享播放器（播放页创建并持有，本页只使用、不 dispose）
  final Player player;

  /// 进入时正在播放的视频路径
  final String initialPath;

  /// 进入时正在播放的视频标题
  final String initialTitle;

  /// 兄弟视频列表（「上一集/下一集」与播放列表用，可空）
  final List<VideoFile>? playlist;

  /// 本页切歌后通知播放页同步最新 path/title
  final void Function(String path, String title)? onVideoChanged;

  const AudioPlayerPage({
    super.key,
    required this.player,
    required this.initialPath,
    required this.initialTitle,
    this.playlist,
    this.onVideoChanged,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  late final Player _player;

  late String _path;
  late String _title;

  /// 播放位置/时长：位置流高频更新只走 ValueNotifier，进度区局部订阅
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  Duration? _dragPosition;

  bool _playing = false;
  double _speed = 1.0;

  /// 当前播放列表（同目录过滤，与播放页播放列表面板一致；为空回退全表）
  late List<VideoFile> _videos;
  int _currentIndex = 0;

  /// 随机播放（本页局部状态，退出不持久化）
  bool _shuffle = false;

  /// 循环模式（本页局部状态）：off / 单曲循环 / 列表循环，
  /// 列表面板里点击循环按钮三态切换（用户反馈：缺少单曲循环）
  _AudioRepeatMode _repeatMode = _AudioRepeatMode.off;

  /// 切歌防重入（open 期间旧文件可能触发 completed）
  bool _isSwitching = false;

  /// 封面帧（居中封面 + 背景高斯模糊共用，RGBA 直通）
  FastThumbFrame? _coverFrame;

  final List<StreamSubscription<dynamic>> _subs = [];

  bool get _hasNext {
    if (_videos.isEmpty) return false;
    return _currentIndex < _videos.length - 1 ||
        _repeatMode == _AudioRepeatMode.loopAll;
  }

  bool get _hasPrevious => _currentIndex > 0 || _repeatMode == _AudioRepeatMode.loopAll;

  @override
  void initState() {
    super.initState();
    _player = widget.player;
    _path = widget.initialPath;
    _title = widget.initialTitle;

    // 从共享播放器当前状态初始化（迟订阅不重放当前值）
    _positionNotifier.value = _player.state.position;
    _durationNotifier.value = _player.state.duration;
    _playing = _player.state.playing;
    // 本界面倍速范围 0.5 – 3.0、步进 0.5：把播放器当前倍速吸附到最近档位，
    // 保证本界面内显示与实测一致（超出范围时收敛进范围）
    final rate = _player.state.rate;
    _speed = _speedOptions().reduce(
      (a, b) => (a - rate).abs() < (b - rate).abs() ? a : b,
    );
    _player.setRate(_speed);

    // 播放列表：同目录过滤（与播放页列表面板一致）；为空回退全表
    final folder = folderOfPath(_path);
    final filtered = filterVideosInFolder(widget.playlist ?? const [], folder);
    _videos = filtered.isEmpty ? (widget.playlist ?? const []) : filtered;
    _currentIndex =
        _videos.indexWhere((v) => v.path == _path).clamp(0, _videos.length - 1);

    // 竖屏 + 沉浸式全屏（状态栏/导航栏隐藏）
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _enterFullscreen();

    _loadCover();

    _subs.add(
      _player.stream.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) _positionNotifier.value = p;
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) _durationNotifier.value = d;
      }),
    );
    // 播放完成：本页处理（切歌/随机/列表循环/停止）
    _subs.add(
      _player.stream.completed.listen((completed) {
        if (completed) _onCompleted();
      }),
    );
  }

  /// 进入沉浸式全屏
  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  /// 取当前视频封面（居中显示 + 背景模糊共用）
  Future<void> _loadCover() async {
    final frame = await DeviceServices.getVideoFrameAt(
      _path,
      _durationNotifier.value.inMilliseconds ~/ 2,
      maxWidth: 480,
    );
    if (!mounted || frame == null) return;
    setState(() => _coverFrame = frame);
  }

  /// 保存当前视频进度（切歌前 / 退出时调用，保证「视频进度还在」）
  Future<void> _saveProgress() async {
    final pos = _positionNotifier.value;
    final dur = _durationNotifier.value;
    if (pos.inMilliseconds > 0 && dur.inMilliseconds > 0 && pos < dur) {
      await PlaybackProgressService.instance.save(
        _path,
        pos,
        forcePersist: true,
      );
    }
  }

  /// 切歌统一入口：保存旧进度 → open → 倍速/超分 → 复位状态。
  /// **不恢复上次进度**：新歌从 0 开始（听歌语义，工作.md 第 10 点）。
  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    if (video.path == _path) return; // 同一首：不动作
    _isSwitching = true;
    await _saveProgress();
    try {
      await _player.open(Media(video.path));
    } on AssertionError {
      // 播放器已被销毁（播放页已退出）：静默返回
      return;
    } finally {
      _isSwitching = false;
    }
    if (!mounted) return;
    _player.setRate(_speed);
    try {
      // 切歌后重放着色器（mpv 打开新文件时着色器链需重新确认）
      await SuperResolutionService.instance.apply(_player);
    } catch (_) {
      // 忽略：超分失败不影响播放
    }
    if (mounted) {
      setState(() {
        _path = video.path;
        _title = video.name;
        _currentIndex = index;
        _positionNotifier.value = Duration.zero;
        _durationNotifier.value = Duration.zero;
        _dragPosition = null;
        _coverFrame = null;
      });
    }
    widget.onVideoChanged?.call(video.path, video.name);
    _loadCover();
  }

  /// 下一首：随机模式用时间刻算法；单曲循环回到当前；否则顺序（列表循环回绕）
  void _next() {
    if (_videos.isEmpty) return;
    if (_repeatMode == _AudioRepeatMode.single) {
      // 单曲循环：seek 0 重播
      _player.seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      final next = audioShuffleNextIndex(
        listLength: _videos.length,
        currentIndex: _currentIndex,
        now: DateTime.now(),
      );
      _switchTo(next);
      return;
    }
    if (_currentIndex < _videos.length - 1) {
      _switchTo(_currentIndex + 1);
    } else if (_repeatMode == _AudioRepeatMode.loopAll) {
      _switchTo(0);
    }
  }

  /// 上一首：随机模式用时间刻算法；单曲循环回到当前；否则顺序（列表循环回绕）
  void _previous() {
    if (_videos.isEmpty) return;
    if (_repeatMode == _AudioRepeatMode.single) {
      _player.seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      final next = audioShuffleNextIndex(
        listLength: _videos.length,
        currentIndex: _currentIndex,
        now: DateTime.now(),
      );
      _switchTo(next);
      return;
    }
    if (_currentIndex > 0) {
      _switchTo(_currentIndex - 1);
    } else if (_repeatMode == _AudioRepeatMode.loopAll) {
      _switchTo(_videos.length - 1);
    }
  }

  /// 播放完成（EOF）：单曲循环重播 → 随机 → 顺序下一首（列表循环回绕）→ 停末尾
  void _onCompleted() {
    if (_isSwitching) return;
    if (!mounted) return;
    if (_durationNotifier.value <= Duration.zero) return;
    if (_positionNotifier.value <
        _durationNotifier.value - const Duration(seconds: 1)) {
      return;
    }
    if (_videos.isEmpty) return;
    if (_repeatMode == _AudioRepeatMode.single) {
      // 单曲循环：seek 0 重播（media_kit seek 会重置 completed，可再次触发）
      _player.seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      final next = audioShuffleNextIndex(
        listLength: _videos.length,
        currentIndex: _currentIndex,
        now: DateTime.now(),
      );
      _switchTo(next);
      return;
    }
    if (_currentIndex < _videos.length - 1) {
      _switchTo(_currentIndex + 1);
    } else if (_repeatMode == _AudioRepeatMode.loopAll) {
      _switchTo(0);
    } else {
      // 最后一首且不循环：停在末尾
      unawaited(_saveProgress());
      _player.seek(_durationNotifier.value);
      _player.pause();
    }
  }

  Future<void> _togglePlay() async {
    await _player.playOrPause();
  }

  void _setSpeed(double v) {
    setState(() => _speed = v);
    _player.setRate(v);
  }

  // ── 底部白色面板（倍速 / 播放列表）────────────────────────

  /// 倍速面板：0.5 – 3.0 步进 0.5，纯白背景，底部弹出带进出场动画。
  /// 用 DraggableScrollableSheet 的控制器限制高度 + 可滚动，避免底部溢出
  ///（用户反馈：Bottom overflowed by 3 pixels）。
  void _openSpeedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                '播放速度',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            // 可滚动区：6 档 + 关闭，小屏不溢出
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in _speedOptions()) ...[
                      ListTile(
                        title: Text(
                          '${s.toStringAsFixed(1)}x',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: (s - _speed).abs() < 0.001
                                ? const Color(0xFF4FC3F7)
                                : const Color(0xFF1A1A1A)
                                    .withValues(alpha: 0.8),
                            fontSize: 16,
                            fontWeight: (s - _speed).abs() < 0.001
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          _setSpeed(s);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                      if (s != _speedOptions().last)
                        const Divider(height: 1, color: Color(0xFFE0E0E0)),
                    ],
                    const Divider(height: 1, color: Color(0xFFE0E0E0)),
                    ListTile(
                      title: const Text(
                        '关闭',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0x661A1A1A),
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<double> _speedOptions() => [0.5, 1.0, 1.5, 2.0, 2.5, 3.0];

  /// 播放列表面板：纯白背景 + 随机播放/循环模式 + 点击切歌。
  /// 高度 = 屏幕 55% 且不超过剩余空间，避免 overflowed（用户反馈）。
  void _openPlaylistSheet() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final sheetHeight =
        (MediaQuery.sizeOf(context).height * 0.55 - bottomInset)
            .clamp(240.0, double.infinity);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    '播放列表',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE0E0E0)),
                // 列表
                Expanded(
                  child: ListView.builder(
                    itemCount: _videos.length,
                    itemBuilder: (context, i) {
                      final cur = i == _currentIndex;
                      final v = _videos[i];
                      return ListTile(
                        dense: true,
                        leading: cur
                            ? const _EqualizerBars(color: Color(0xFF4FC3F7))
                            : const SizedBox(width: 14, height: 14),
                        title: Text(
                          v.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cur
                                ? const Color(0xFF4FC3F7)
                                : const Color(0xFF1A1A1A)
                                    .withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight:
                                cur ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _switchTo(i);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE0E0E0)),
                // 底部：随机播放 / 循环模式（关闭→单曲→列表，三态切换）
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SheetToggle(
                        icon: Icons.shuffle_rounded,
                        label: '随机播放',
                        active: _shuffle,
                        onTap: () {
                          setSheetState(() => _shuffle = !_shuffle);
                        },
                      ),
                      const SizedBox(width: 16),
                      _SheetToggle(
                        icon: _repeatMode == _AudioRepeatMode.single
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        label: _repeatMode.label,
                        active: _repeatMode != _AudioRepeatMode.off,
                        onTap: () {
                          setSheetState(() {
                            _repeatMode = _repeatMode.next;
                          });
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

  // ── 退出 ───────────────────────────────────────────────

  Future<void> _exit() async {
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_saveProgress()); // dispose 无法 await，交给后台链完成
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    // 注意：不 dispose 播放器——播放页持有
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inMilliseconds);

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF64B5F6);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 背景：封面高斯模糊 + 深色蒙层
            Positioned.fill(
              child: _coverFrame == null
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1A)],
                        ),
                      ),
                    )
                  : ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 40,
                        sigmaY: 40,
                      ),
                      child: RawThumbImage(
                        frame: _coverFrame!,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.72)),
            ),
            // 主内容
            SafeArea(
              child: Column(
                children: [
                  // 顶栏：返回 + 「听视频」
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white70,
                            size: 26,
                          ),
                          tooltip: '返回',
                          onPressed: _exit,
                        ),
                        const Expanded(
                          child: Text(
                            '听视频',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 居中封面 16:9
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(
                                color: const Color(0xFF2A2A2A),
                                child: _coverFrame == null
                                    ? const Icon(
                                        Icons.headphones_outlined,
                                        color: Colors.white24,
                                        size: 48,
                                      )
                                    : RawThumbImage(
                                        frame: _coverFrame!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 标题
                          Text(
                            _title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // 进度条 + 时间
                          ListenableBuilder(
                            listenable: Listenable.merge([
                              _positionNotifier,
                              _durationNotifier,
                            ]),
                            builder: (context, _) {
                              final pos = _dragPosition ?? _positionNotifier.value;
                              final dur = _durationNotifier.value;
                              final fraction = dur.inMilliseconds > 0
                                  ? (pos.inMilliseconds / dur.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0;
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      activeTrackColor: accentColor,
                                      inactiveTrackColor:
                                          Colors.white.withValues(alpha: 0.15),
                                      thumbColor: accentColor,
                                      overlayColor: accentColor.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    child: Slider(
                                      value: fraction,
                                      onChanged: (v) {
                                        setState(() {
                                          _dragPosition = Duration(
                                            milliseconds:
                                                (v * dur.inMilliseconds)
                                                    .round(),
                                          );
                                        });
                                      },
                                      onChangeEnd: (v) {
                                        _player.seek(Duration(
                                          milliseconds:
                                              (v * dur.inMilliseconds).round(),
                                        ));
                                        setState(() => _dragPosition = null);
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _fmt(pos),
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          _fmt(dur),
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // 底部控制卡：倍速 | 上一集 | 播放/暂停 | 下一集 | 播放列表
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _AudioControlButton(
                                  icon: Icons.speed_rounded,
                                  label: '${_speed.toStringAsFixed(1)}x',
                                  onTap: _openSpeedSheet,
                                ),
                                _AudioControlButton(
                                  icon: Icons.skip_previous_rounded,
                                  enabled: _hasPrevious,
                                  onTap: _previous,
                                ),
                                // 播放/暂停（大按钮）
                                IconButton(
                                  iconSize: 44,
                                  icon: Icon(
                                    _playing
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                  onPressed: _togglePlay,
                                ),
                                _AudioControlButton(
                                  icon: Icons.skip_next_rounded,
                                  enabled: _hasNext,
                                  onTap: _next,
                                ),
                                _AudioControlButton(
                                  icon: Icons.queue_music_rounded,
                                  onTap: _openPlaylistSheet,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 听视频循环模式：关闭 → 单曲循环 → 列表循环（点击循环按钮循环切换）
enum _AudioRepeatMode {
  off('循环关闭'),
  single('单曲循环'),
  loopAll('列表循环');

  final String label;
  const _AudioRepeatMode(this.label);

  /// 三态循环：off → single → loopAll → off
  _AudioRepeatMode get next => switch (this) {
        _AudioRepeatMode.off => _AudioRepeatMode.single,
        _AudioRepeatMode.single => _AudioRepeatMode.loopAll,
        _AudioRepeatMode.loopAll => _AudioRepeatMode.off,
      };
}

/// 底部控制卡里的小按钮：图标 +（可选）小字标签，48×48 触摸区。
/// 全部按钮统一 [height]（含标签的倍速按钮与纯图标按钮高度一致，
/// 用户反馈：上一版倍速按钮因下方倍数文本比其他按钮高、不平行）。
class _AudioControlButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool enabled;
  final VoidCallback onTap;

  /// 统一按钮高度（含标签）；无标签按钮图标垂直居中同一高度
  static const double height = 52;

  const _AudioControlButton({
    required this.icon,
    this.label,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: Colors.white.withValues(alpha: enabled ? 1 : 0.3),
            ),
            // 标签行固定占位：无标签按钮也保留相同高度，保证五按钮平行
            SizedBox(
              height: 14,
              child: label == null || !enabled
                  ? null
                  : Text(
                      label!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 10,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放列表面板底部的开关胶囊（随机播放 / 列表循环）
class _SheetToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SheetToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF64B5F6);
    const inactiveColor = Color(0xFF1A1A1A);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? accentColor
                : const Color(0xFFD9D9DE),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? accentColor : inactiveColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? accentColor : inactiveColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前播放项的等化器跳动动画（三根竖条交错跳动，用户反馈旧版
/// 只有一节在跳——用正弦错相让三根条各自独立起伏，更灵动好看）。
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
          // ⚠️ 用 spaceBetween + 不加 padding：3 根条共 9px 放进 14px 容器，
          // 剩余空间均分，永不会溢出。旧实现每根条带 1px 左右 padding
          //（3+2）×3 = 15px > 14px，触发行溢出
          //（用户反馈 v4：播放列表面板最左侧 right overflowed by 1 pixels）。
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 3,
                  // 三根条相位各差 1/3 周期，正弦独立起伏（0.35–1.0）
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

  /// 三根条错相起伏：0 / 1/3 / 2/3 相位差的正弦，恒 > 0 不触底
  double _barFactor(double t, int index) {
    final phase = (t + index / 3) % 1.0;
    // 0.35 + 0.65 * ((1 - cos(2π·phase)) / 2)：0.35..1.0 平滑起伏
    return 0.35 + 0.65 * (1 - _cos2pi(phase * 2)) / 2;
  }

  static double _cos2pi(double x) {
    // 简易余弦近似（-1..1），避免引入额外依赖
    final xx = x - x.roundToDouble();
    return 1 - 2 * xx * xx * (3 - 2 * xx.abs());
  }
}
