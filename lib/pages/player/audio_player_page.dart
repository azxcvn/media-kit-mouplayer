import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/views/audio_player_panels.dart';
import 'package:moumou/pages/player/views/player_play_pause_button.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/fast_thumbnails.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/utils/audio_shuffle.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/raw_thumb_image.dart';

/// 听视频界面（工作.md 第 10 点 + 阶段1 第 2 点重设计，参考小喵 KT 项目 AudioPlayerScreen）：
///
/// - 竖屏全屏独立界面，**共享横屏/竖屏播放页的同一个 [Player]**——
///   不新建播放器、不 open、不恢复进度（同一会话音频零中断）；
/// - **后台播放**（阶段1 第 2 点）：进入本页即启动前台服务保活进程，
///   退到后台后像音乐播放器一样继续播放，退出本页时停止服务；
/// - 只播放音频不显示视频：整页被封面高斯模糊背景覆盖，画面完全隐藏，
///   退出后播放页从当前进度继续显示视频；
/// - 布局：顶栏（返回 + 「听视频」）+ 居中封面（1:1 圆角）+ 标题 +
///   进度条（拖动 seek）+ 底部控制卡（倍速 | 上一集 | 播放/暂停 | 下一集 |
///   播放列表）；播放/暂停与其余按钮同尺寸同水平线，切换带图标形变动画；
/// - 倍速范围 **0.5 – 3.0，步进 0.5**；倍速/播放列表面板为**深色胶囊风格**
///   （见 [audio_player_panels.dart]），均带右上角关闭按钮；
/// - **定时关闭**（阶段1 第 2 点）：15/30/60 分钟或播完当前曲目，到时自动暂停；
/// - 列表面板支持**随机播放**（时间刻算法 [audioShuffleNextIndex]）与**列表循环**；
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
  AudioRepeatMode _repeatMode = AudioRepeatMode.off;

  // ── 定时关闭（工作.md 阶段1 第 2 点）────────────────────

  /// 当前定时关闭预设（默认关闭）
  AudioSleepPreset _sleepPreset = AudioSleepPreset.off;

  /// 倒计时剩余时长（仅定时预设激活时非 null）
  Duration? _sleepRemaining;

  /// 倒计时定时器（每秒递减 [_sleepRemaining]）
  Timer? _sleepTimer;

  /// 「播完当前曲目」标志：到 EOF 时暂停且不切下一首
  bool _sleepPauseAtTrackEnd = false;

  /// 切歌防重入（open 期间旧文件可能触发 completed）
  bool _isSwitching = false;

  /// 封面帧（居中封面 + 背景高斯模糊共用，RGBA 直通）
  FastThumbFrame? _coverFrame;

  final List<StreamSubscription<dynamic>> _subs = [];

  bool get _hasNext {
    if (_videos.isEmpty) return false;
    return _currentIndex < _videos.length - 1 ||
        _repeatMode == AudioRepeatMode.loopAll;
  }

  bool get _hasPrevious =>
      _currentIndex > 0 || _repeatMode == AudioRepeatMode.loopAll;

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

    // 后台播放（工作.md 阶段1 第 2 点）：启动前台服务保活进程，
    // 使音频在退到后台后像音乐播放器一样继续播放；退出本页时停止。
    DeviceServices.startBackgroundPlayback(title: _title);

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
    // 后台播放：刷新前台服务通知标题为新曲目（服务已在运行，重复启动仅更新）
    DeviceServices.startBackgroundPlayback(title: video.name);
    _loadCover();
  }

  /// 下一首：随机模式用时间刻算法；单曲循环回到当前；否则顺序（列表循环回绕）
  void _next() {
    if (_videos.isEmpty) return;
    if (_repeatMode == AudioRepeatMode.single) {
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
    } else if (_repeatMode == AudioRepeatMode.loopAll) {
      _switchTo(0);
    }
  }

  /// 上一首：随机模式用时间刻算法；单曲循环回到当前；否则顺序（列表循环回绕）
  void _previous() {
    if (_videos.isEmpty) return;
    if (_repeatMode == AudioRepeatMode.single) {
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
    } else if (_repeatMode == AudioRepeatMode.loopAll) {
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
    if (_sleepPauseAtTrackEnd) {
      // 定时关闭「播完当前曲目」：暂停并清除标志，不切下一首（工作.md 阶段1 第 2 点）
      _sleepPauseAtTrackEnd = false;
      _sleepPreset = AudioSleepPreset.off;
      unawaited(_saveProgress());
      _player.pause();
      if (mounted) setState(() {});
      return;
    }
    if (_repeatMode == AudioRepeatMode.single) {
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
    } else if (_repeatMode == AudioRepeatMode.loopAll) {
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

  // ── 定时关闭（工作.md 阶段1 第 2 点）────────────────────

  /// 应用定时关闭预设：
  /// - off：取消倒计时与「播完当前」标志；
  /// - min15/30/60 / custom：启动每秒倒计时，归零后暂停播放；
  ///   custom 用 [custom] 指定时长；
  /// - trackEnd：到当前曲目 EOF 时暂停（见 [_onCompleted]）。
  void _applySleepPreset(AudioSleepPreset p, {Duration? custom}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = null;
    _sleepPauseAtTrackEnd = false;
    _sleepPreset = p;
    switch (p) {
      case AudioSleepPreset.off:
        break;
      case AudioSleepPreset.trackEnd:
        _sleepPauseAtTrackEnd = true;
        break;
      case AudioSleepPreset.custom:
        _sleepRemaining = custom ?? const Duration(minutes: 15);
        _startSleepCountdown();
        break;
      case AudioSleepPreset.min15:
      case AudioSleepPreset.min30:
      case AudioSleepPreset.min60:
        _sleepRemaining = p.duration;
        _startSleepCountdown();
        break;
    }
    if (mounted) setState(() {});
  }

  /// 启动每秒倒计时，归零后暂停播放
  void _startSleepCountdown() {
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rem = _sleepRemaining;
      if (rem == null) return;
      final next = rem - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        // 到时：暂停播放并清除定时
        _sleepTimer?.cancel();
        _sleepTimer = null;
        _sleepRemaining = null;
        _sleepPreset = AudioSleepPreset.off;
        _player.pause();
        if (mounted) setState(() {});
      } else {
        _sleepRemaining = next;
        if (mounted) setState(() {});
      }
    });
  }

  // ── 底部面板（倍速 / 播放列表，胶囊式重设计，工作.md 阶段1 第 2 点）──

  static List<double> _speedOptions() =>
      [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];

  /// 倍速面板：倍速档位胶囊 + 定时关闭预设，右上角关闭按钮
  void _openSpeedSheet() {
    showAudioSpeedSheet(
      context,
      speed: _speed,
      options: _speedOptions(),
      onSpeed: _setSpeed,
      sleepPreset: _sleepPreset,
      onSleepPreset: _applySleepPreset,
      sleepRemaining: _sleepRemaining ?? Duration.zero,
    );
  }

  /// 播放列表面板：曲目列表 + 随机/循环胶囊，右上角关闭按钮
  void _openPlaylistSheet() {
    showAudioPlaylistSheet(
      context,
      videos: _videos,
      currentIndex: _currentIndex,
      shuffle: _shuffle,
      repeatMode: _repeatMode,
      onSelect: _switchTo,
      onToggleShuffle: () => setState(() => _shuffle = !_shuffle),
      onCycleRepeat: () => setState(() => _repeatMode = _repeatMode.next),
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
    // 定时关闭定时器清理 + 后台播放前台服务停止（工作.md 阶段1 第 2 点）
    _sleepTimer?.cancel();
    DeviceServices.stopBackgroundPlayback();
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
                          // 居中封面 1:1 圆角（缩小：约屏宽 50%、上限 240dp，避免过大）
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width * 0.5)
                                .clamp(0.0, 240.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  color: const Color(0xFF2A2A2A),
                                  child: _coverFrame == null
                                      ? const Icon(
                                          Icons.headphones_outlined,
                                          color: Colors.white24,
                                          size: 40,
                                        )
                                      : RawThumbImage(
                                          frame: _coverFrame!,
                                          fit: BoxFit.cover,
                                        ),
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
                                // 播放/暂停：与其它四按钮同 52×52 触摸区、同内部结构
                                //（图标 26 + 14 标签槽），保证五个按钮图标在同一水平线；
                                // 用 [PlayerPlayPauseButton] 图标形变动画消除生硬切换。
                                SizedBox(
                                  width: 52,
                                  height: _AudioControlButton.height,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _togglePlay,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        PlayerPlayPauseButton(
                                          playing: _playing,
                                          iconSize: 26,
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                    ),
                                  ),
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

/// 底部控制卡里的小按钮：图标 +（可选）小字标签，48×48 触摸区。
/// 全部按钮统一 [height]（含标签）；无标签按钮图标垂直居中同一高度
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
