import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/views/player_center_cluster.dart';
import 'package:moumou/pages/player/views/player_fit_panel.dart';
import 'package:moumou/pages/player/views/player_gesture_indicator.dart';
import 'package:moumou/pages/player/views/player_gesture_layer.dart';
import 'package:moumou/pages/player/views/player_loop_panel.dart';
import 'package:moumou/pages/player/views/player_playlist_panel.dart';
import 'package:moumou/pages/player/views/player_speed_indicator.dart';
import 'package:moumou/pages/player/views/player_speed_panel.dart';
import 'package:moumou/pages/player/views/player_super_resolution_panel.dart';
import 'package:moumou/pages/player/views/player_swipe_seek_overlay.dart';
import 'package:moumou/pages/player/views/player_right_actions.dart';
import 'package:moumou/pages/player/views/portrait_edit_panel.dart';
import 'package:moumou/pages/player/views/portrait_player_bottom_bar.dart';
import 'package:moumou/pages/player/views/portrait_player_top_bar.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/utils/playback_completion.dart';
import 'package:moumou/utils/playback_restore.dart';
import 'package:moumou/utils/player_gestures.dart';
import 'package:moumou/widgets/player_bottom_panel.dart';
import 'package:moumou/widgets/player_panel.dart';
import 'package:saver_gallery/saver_gallery.dart';

/// 竖屏播放页（工作.md 第 17 点）：独立 dart 文件，不与横屏 [PlayerPage] 共用。
///
/// v3 重构（对齐 KT 项目丝滑横竖屏切换）：**横竖屏共享同一个 [Player] /
/// [VideoController]**——本页不创建播放器、不 open、不恢复进度（同一会话），
/// 切换只是把同一路画面换成竖屏布局渲染，**音频零中断、无黑屏、无重新加载**。
/// 播放器生命周期/设备状态（音量/亮度）由横屏页（push 方）统一持有与恢复；
/// 本页退出（pop）后横屏页立即恢复横屏方向与沉浸式全屏。
///
/// 布局：
/// - 顶部：返回 + 视频标题 + 自定义槽位（最多 4 个）+ 固定「更多」按钮；
/// - 中央：快退 / 播放暂停 / 快进（复用 [PlayerCenterCluster]）；
/// - 底部：进度条（复用 [PlayerSeekBar]）+ 下一集 + 时间（点击切换
///   「已播/总时长」⇄「已播/剩余时长」）+ 右侧按钮簇
///   （从右到左：选择屏幕 → 倍速 → 列表 → 超分辨率）；
/// - 二级界面（倍速 / 超分 / 画面比例 / 更多 / 编辑控制栏 / 播放列表）
///   一律从底部弹出（[showPlayerBottomPanel]）；
/// - 全套手势（音量/亮度/水平 seek/长按倍速），与横屏同一裸识别器方案。
///
/// 由横屏页右下角「选择屏幕」push（带播放页路由标识），退出即返回横屏。
class PlayerPortraitPage extends StatefulWidget {
  /// 共享播放器（横屏页创建并持有，本页只使用、不 dispose）
  final Player player;

  /// 共享视频控制器（同一路画面）
  final VideoController controller;

  /// 进入时正在播放的视频路径
  final String initialPath;

  /// 进入时正在播放的视频标题
  final String initialTitle;

  /// 兄弟视频列表（「下一集」与播放列表用，可空）
  final List<VideoFile>? playlist;

  /// 本页切集后通知横屏页同步最新 path/title
  final void Function(String path, String title)? onVideoChanged;

  /// 本页 EOF「自动退出」时回调（横屏页先关本页再退出播放器回到列表）
  final VoidCallback? onExitPlayer;

  const PlayerPortraitPage({
    super.key,
    required this.player,
    required this.controller,
    required this.initialPath,
    required this.initialTitle,
    this.playlist,
    this.onVideoChanged,
    this.onExitPlayer,
  });

  @override
  State<PlayerPortraitPage> createState() => _PlayerPortraitPageState();
}

class _PlayerPortraitPageState extends State<PlayerPortraitPage> {
  late final Player _player;
  late final VideoController _controller;
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  late String _path;
  late String _title;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  double _speed = 1.0;

  /// 实际倍速的监听器：倍速底部面板通过它实时刷新
  final ValueNotifier<double> _speedNotifier = ValueNotifier(1.0);

  /// 控制层显隐（单击切换，播放中 3 秒自动隐藏）
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// 手势指示器（音量/亮度共用，2 秒无操作自动隐藏）
  ({GestureIndicatorKind kind, double value})? _indicator;
  GestureIndicatorKind? _indicatorKind;
  Timer? _indicatorHideTimer;

  /// 当前应用音量（0 – 100，进入时从系统/窗口同步，仅作指示器基准；
  /// 音量/亮度改动直控系统/窗口，本页不负责退出恢复——横屏页统一处理）
  double _volume = 50;
  double _brightness = 1.0;
  double _volumeAccum = 0;
  double _brightnessAccum = 0;

  /// 水平滑动 seek 相关
  Duration _swipeSeekStart = Duration.zero;
  ({Duration target, Duration delta})? _swipeSeekData;
  bool _swipeSeekVisible = false;
  Timer? _swipeSeekClearTimer;
  DateTime? _lastSwipeSeekTime;

  /// 长按倍速
  bool _longPressing = false;
  double? _speedBeforeLongPress;
  double _longPressSpeed = 2.0;
  Offset? _longPressStartPos;
  int _dynamicStartIndex = 0;
  bool _dynamicSpeedActive = false;
  bool _speedBarVisible = false;
  Timer? _speedBarTimer;

  /// 双击 seek 反馈
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  /// 时间文本显示剩余时长（点击切换，工作.md 第 20 点）
  bool _showRemaining = false;

  /// 控制层是否锁定（锁定后隐藏全部控制；左右两侧出现解锁按钮，
  /// 单击屏幕可呼出/隐藏解锁按钮——与横屏一致）
  bool _locked = false;
  bool _unlockVisible = false;

  /// 当前视口尺寸（手势计算用，build 时更新）
  double _viewportWidth = 0;
  double _viewportHeight = 0;

  /// 防重入标志（与横屏一致；共享播放器下 EOF 由本页处理）
  bool _isSwitchingVideo = false;
  bool _isHandlingEndOfFile = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// 是否存在「下一集」（playlist 中当前视频之后还有视频）
  bool get _hasNext {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return false;
    final idx = list.indexWhere((v) => v.path == _path);
    return idx >= 0 && idx < list.length - 1;
  }

  @override
  void initState() {
    super.initState();
    _player = widget.player;
    _controller = widget.controller;
    _path = widget.initialPath;
    _title = widget.initialTitle;

    // 从共享播放器**当前状态**初始化（media_kit 流是广播流，迟订阅不会重放
    // 当前值；暂停/静置时无新事件——必须读 state，否则位置/时长/播放态
    // 显示为 0/错误，进度条呈"已播完"样式）
    _position = _player.state.position;
    _duration = _player.state.duration;
    _playing = _player.state.playing;

    // 倍速展示：跟随共享播放器当前设置（不 setRate，横屏已应用）
    _speed = _settings.rememberSpeed ? _settings.lastSpeed : 1.0;
    _speedNotifier.value = _speed;

    // 手势指示器基准：从系统/窗口同步（不锁窗口亮度——横屏已锁）
    _initGestureState();

    // 竖屏 + 沉浸式全屏（状态栏/导航栏隐藏）
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _enterFullscreen();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterFullscreen());
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _enterFullscreen();
    });

    _subs.add(
      _player.stream.playing.listen((p) {
        if (!mounted) return;
        setState(() {
          _playing = p;
          // 暂停时总是显示控制层（含中央播放键）
          if (!p) _controlsVisible = true;
        });
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    // 播放完成（EOF）：共享播放器，本页在栈顶期间负责处理
    // （横屏页已通过 _portraitActive 让位）
    _subs.add(
      _player.stream.completed.listen((completed) {
        if (completed) _onPlaybackCompleted();
      }),
    );

    _resetHideTimer();
  }

  /// 手势指示器基准（音量/亮度），不改任何系统/窗口状态
  Future<void> _initGestureState() async {
    final vol = await DeviceServices.getSystemVolume();
    if (vol != null) _volume = vol;
    final brightness = await DeviceServices.getBrightness();
    if (brightness != null) _brightness = brightness;
    if (mounted) setState(() {});
  }

  /// 进入沉浸式全屏：隐藏状态栏/导航栏，并把系统栏设为透明
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

  // ── 控制层显隐 ──────────────────────────────────────────

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_locked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    // 锁定时单击：呼出/隐藏左右解锁按钮（与横屏一致）
    if (_locked) {
      setState(() => _unlockVisible = !_unlockVisible);
      return;
    }
    final visible = !_controlsVisible;
    setState(() => _controlsVisible = visible);
    if (visible) {
      _resetHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ── 锁定 / 解锁 ─────────────────────────────────────────

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) {
        _unlockVisible = false;
        _controlsVisible = false;
        _hideTimer?.cancel();
      } else {
        _unlockVisible = false;
        _controlsVisible = true;
        _resetHideTimer();
      }
    });
  }

  void _unlock() => _toggleLock();

  // ── 截图 ────────────────────────────────────────────────

  Future<void> _takeScreenshot() async {
    Uint8List? bytes;
    try {
      bytes = await _player.screenshot(format: 'image/png');
    } catch (e) {
      _toast('截图失败：$e');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _toast('截图失败：未获取到图像');
      return;
    }
    try {
      final name = 'moumou_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: name,
        skipIfExists: false,
      );
      _toast(result.isSuccess ? '已保存到相册' : '截图保存失败：${result.errorMessage}');
    } catch (e) {
      _toast('截图保存失败：$e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── 播放控制 ────────────────────────────────────────────

  Future<void> _togglePlay() async {
    await _player.playOrPause();
    _resetHideTimer();
  }

  Future<void> _seekBy(int seconds) async {
    final total = _duration.inMilliseconds;
    final target = (_position + Duration(seconds: seconds))
        .inMilliseconds
        .clamp(0, total);
    await _player.seek(Duration(milliseconds: target));
    _showSeekFeedback(seconds >= 0 ? '+$seconds' : '$seconds');
    _resetHideTimer();
  }

  /// 双击手势（暂停 / 左退右进 / 混合，跟随设置）
  void _handleDoubleTap(double dx, double width) {
    final gesture = classifyDoubleTap(dx, width, _settings.doubleTapMode);
    switch (gesture) {
      case DoubleTapGesture.pauseToggle:
        _togglePlay();
      case DoubleTapGesture.seekBackward:
        _seekBy(-_settings.seekSeconds);
      case DoubleTapGesture.seekForward:
        _seekBy(_settings.seekSeconds);
    }
  }

  // ── 手势（与横屏 PlayerPage 同一套）───────────────────
  // 竖屏方向：亮度在左半屏、音量在右半屏、水平滑动 seek
  // （右侧 8% 死区由 PlayerGestureLayer 处理）；无锁定、无双指缩放。

  void _showSeekFeedback(String text) {
    _seekFeedbackTimer?.cancel();
    if (mounted) setState(() => _seekFeedback = text);
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _showIndicator(GestureIndicatorKind kind, double value) {
    _indicatorHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _indicatorKind = kind;
        _indicator = (kind: kind, value: value);
      });
    }
    _indicatorHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _indicator = null);
    });
  }

  void _onVerticalSwipe(double dyDelta, bool isLeftHalf) {
    if (_viewportHeight <= 0) return;
    if (isLeftHalf) {
      // 左侧：亮度（直控窗口亮度；退出恢复由横屏页统一处理）
      _brightnessAccum +=
          brightnessDeltaForSwipe(
            dyDelta,
            _viewportHeight,
            _settings.brightnessSensitivity,
          ) *
          100;
      final intDelta = _brightnessAccum.truncate();
      if (intDelta != 0) {
        _brightnessAccum -= intDelta;
        final newB = (_brightness * 100 + intDelta).clamp(0.0, 100.0) / 100;
        if ((newB - _brightness).abs() > 0.0001) {
          _brightness = newB;
          DeviceServices.setWindowBrightness(newB);
          _showIndicator(GestureIndicatorKind.brightness, newB);
        }
      }
    } else {
      // 右侧：音量（直控系统媒体音量 = 真实响度）
      _volumeAccum +=
          volumeDeltaForSwipe(
            dyDelta,
            _viewportHeight,
            _settings.volumeSensitivity,
          );
      final intDelta = _volumeAccum.truncate();
      if (intDelta != 0) {
        _volumeAccum -= intDelta;
        final newV = (_volume + intDelta).clamp(0.0, 100.0);
        if ((newV - _volume).abs() > 0.001) {
          _volume = newV;
          DeviceServices.setSystemVolume(newV);
          _showIndicator(GestureIndicatorKind.volume, newV);
        }
      }
    }
  }

  void _onSwipeStart() {
    _swipeSeekStart = _position;
    _volumeAccum = 0;
    _brightnessAccum = 0;
    _hideTimer?.cancel();
  }

  void _onHorizontalSwipe(double totalDx) {
    if (_duration <= Duration.zero) return;
    final target = swipeSeekTarget(
      _swipeSeekStart,
      totalDx,
      _viewportWidth,
      _duration,
    );
    final now = DateTime.now();
    if (_lastSwipeSeekTime == null ||
        now.difference(_lastSwipeSeekTime!) >= const Duration(milliseconds: 40)) {
      _lastSwipeSeekTime = now;
      _player.seek(target);
    }
    _swipeSeekClearTimer?.cancel();
    if (mounted) {
      setState(() {
        _swipeSeekData = (target: target, delta: target - _swipeSeekStart);
        _swipeSeekVisible = true;
      });
    }
  }

  void _onSwipeEnd() {
    _swipeSeekVisible = false;
    _lastSwipeSeekTime = null;
    _swipeSeekClearTimer?.cancel();
    _swipeSeekClearTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _swipeSeekData = null);
    });
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  // ── 长按倍速 ───────────────────────────────────────────

  void _onLongPressStart(Offset pos) {
    _speedBeforeLongPress = _speed;
    _longPressStartPos = pos;
    _longPressSpeed = _settings.longPressSpeed;
    _dynamicStartIndex = nearestSpeedPresetIndex(
      _settings.longPressSpeed,
      dynamicSpeedPresets(),
    );
    _dynamicSpeedActive = false;
    _speedBarVisible = false;
    _longPressing = true;
    _player.setRate(_longPressSpeed);
    _hideTimer?.cancel();
    if (mounted) setState(() {});
  }

  void _onLongPressUpdate(Offset pos) {
    final start = _longPressStartPos;
    if (start == null || !_longPressing) return;
    if (_viewportWidth <= 0) return;
    final presets = dynamicSpeedPresets();
    final dx = pos.dx - start.dx;
    final newIndex = dynamicSpeedIndex(
      dx,
      _viewportWidth,
      _dynamicStartIndex,
      presets.length,
    );
    final newSpeed = presets[newIndex];
    if ((newSpeed - _longPressSpeed).abs() < 0.01) return;
    _longPressSpeed = newSpeed;
    _player.setRate(newSpeed);
    _dynamicSpeedActive = true;
    _speedBarVisible = true;
    _settings.markSpeedHintShown();
    _speedBarTimer?.cancel();
    _speedBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _speedBarVisible = false);
    });
    if (mounted) setState(() {});
  }

  void _onLongPressEnd() {
    if (!_longPressing) return;
    _longPressing = false;
    _speedBarTimer?.cancel();
    _speedBarVisible = false;
    _dynamicSpeedActive = false;
    final restore = _speedBeforeLongPress ?? _speed;
    _speedBeforeLongPress = null;
    _longPressStartPos = null;
    _player.setRate(restore);
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  // ── 下一集 / 播放列表切集 ───────────────────────────────

  Future<void> _playNext() async {
    final list = widget.playlist;
    if (list == null) return;
    final idx = list.indexWhere((v) => v.path == _path);
    if (idx < 0 || idx >= list.length - 1) return;
    final next = list[idx + 1];
    await _switchTo(next.path, next.name);
  }

  /// 切集统一入口（「下一集」/「列表循环回第一集」/播放列表面板点击共用，
  /// 工作.md 第 8 点）：共享播放器上直接切集（音频连续），
  /// 保存当前进度 → open → 倍速/超分 → 恢复新集记忆进度。
  Future<void> _switchTo(String path, String name) async {
    _isSwitchingVideo = true;
    _saveProgress();
    try {
      await _player.open(Media(path));
      _player.setRate(_speed);
      // 切集后重放着色器（mpv 打开新文件时着色器链需重新确认）
      await SuperResolutionService.instance.apply(_player);
    } finally {
      _isSwitchingVideo = false;
    }
    if (mounted) {
      setState(() {
        _path = path;
        _title = name;
        _position = Duration.zero;
        _duration = Duration.zero;
        _dragPosition = null;
        _indicator = null;
        _swipeSeekData = null;
      });
    }
    // 通知横屏页同步最新 path/title（共享播放器，横屏侧状态必须跟随）
    widget.onVideoChanged?.call(path, name);
    // 新集恢复其记忆进度（<30s 短视频不恢复，与横屏语义一致）
    await _restoreProgressForNewVideo();
    _resetHideTimer();
  }

  /// 恢复新集记忆进度（仅切集时调用；进入竖屏页本身不恢复——同一会话）。
  /// 短视频（<30s）不恢复（参考 src loadVideo）；看完阈值用设置。
  Future<void> _restoreProgressForNewVideo() async {
    final saved = PlaybackProgressService.instance.getProgress(_path);
    if (saved == null || saved <= Duration.zero) return;
    if (_player.state.duration > Duration.zero &&
        _player.state.duration < const Duration(seconds: 30)) {
      return;
    }
    await restorePlaybackPosition(
      _player,
      saved,
      maxRestoreRatio: _settings.watchThreshold,
    );
  }

  /// 列表循环：回到播放列表第一集。
  Future<void> _playFirst() async {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return;
    final first = list.first;
    await _switchTo(first.path, first.name);
  }

  /// 底栏「列表」按钮：底部弹出播放列表面板（工作.md 第 7 点）。
  Future<void> _openPlaylistPanel() async {
    _hideTimer?.cancel();
    final folder = folderOfPath(_path);
    final videos = filterVideosInFolder(widget.playlist ?? const [], folder);
    await showPlayerBottomPanel(
      context,
      pages: [
        PlayerPanelPage(
          title: '播放列表',
          body: PlayerPlaylistPanel(
            videos: videos,
            currentPath: _path,
            onSelect: (video) {
              if (video.path == _path) return; // 选当前项：不动作
              _switchTo(video.path, video.name);
            },
          ),
        ),
      ],
    );
    _resetHideTimer();
  }

  // ── 播放完成（EOF）──────────────────────────────────────

  /// 播放完成处理：与横屏 [PlayerPage] 同一逻辑（参考 kt `handleEndOfFile()`
  /// 优先级链：单集循环 → 自动连播 → 列表循环 → 自动退出 → 自动暂停）。
  /// 共享播放器下，竖屏页在栈顶期间负责处理 completed（横屏已让位）。
  void _onPlaybackCompleted() {
    if (_isSwitchingVideo || _isHandlingEndOfFile) return;
    if (!mounted) return;
    if (_duration <= Duration.zero) return;
    if (_position < _duration - const Duration(seconds: 1)) return;
    _isHandlingEndOfFile = true;
    try {
      final action = resolveEndOfFileAction(
        loopMode: _settings.loopMode,
        autoNext: _settings.autoNext,
        autoExit: _settings.autoExit,
        hasPlaylist: widget.playlist?.isNotEmpty ?? false,
        hasNext: _hasNext,
      );
      switch (action) {
        case EndOfFileAction.replayCurrent:
          _player.seek(Duration.zero);
          _player.play();
        case EndOfFileAction.playNext:
          _markCompleted();
          _playNext();
        case EndOfFileAction.playFirst:
          _markCompleted();
          _playFirst();
        case EndOfFileAction.exitPlayer:
          // 自动退出：先记已看完，再让横屏页关掉本页并退出播放器（回到列表）
          _markCompleted();
          widget.onExitPlayer?.call();
        case EndOfFileAction.pauseAtEnd:
          _markCompleted();
          _player.seek(_duration);
          _player.pause();
      }
    } finally {
      _isHandlingEndOfFile = false;
    }
  }

  /// 播放到结尾：把进度记为「已看完」（= 时长），视频列表据此显示已看完。
  void _markCompleted() {
    if (_duration <= Duration.zero) return;
    PlaybackProgressService.instance.save(_path, _duration);
  }

  // ── 倍速 ────────────────────────────────────────────────

  void _setSpeed(double v, {bool remember = true}) {
    _speed = v;
    _speedNotifier.value = v; // 通知倍速面板实时刷新
    _player.setRate(v);
    if (remember) _settings.setSpeed(v);
    if (mounted) setState(() {});
  }

  // ── 底部面板（倍速 / 超分 / 画面比例 / 更多 / 编辑控制栏）────

  PlayerPanelPage _speedPanelPage() => PlayerPanelPage(
        title: '播放倍速',
        body: PlayerSpeedPanel(
          speedListenable: _speedNotifier,
          onSpeedChanged: _setSpeed,
          onTemporaryApply: (v) => _setSpeed(v, remember: false),
          onReset: () => _setSpeed(1.0),
        ),
      );

  PlayerPanelPage _superResolutionPanelPage() => PlayerPanelPage(
        title: '超分辨率',
        body: PlayerSuperResolutionPanel(player: _player),
      );

  PlayerPanelPage _fitPanelPage() => PlayerPanelPage(
        title: '画面比例',
        body: const PlayerFitPanel(),
      );

  PlayerPanelPage _loopPanelPage() => PlayerPanelPage(
        title: '循环播放',
        body: const PlayerLoopPanel(),
      );

  /// 「更多」面板主页：已启用槽位动作 +「编辑控制栏」入口。
  Widget _buildMorePanel() {
    return Builder(
      builder: (panelContext) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final enabled = _settings.topActions;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final a in enabled)
                PortraitPanelActionTile(
                  icon: a.icon,
                  label: a.label,
                  subtitle: !a.implemented ? '功能即将上线' : null,
                  onTap: () => _handlePanelAction(panelContext, a),
                ),
              if (enabled.isNotEmpty)
                const Divider(height: 1, color: Colors.white12),
              PortraitPanelActionTile(
                icon: Icons.tune,
                label: '编辑控制栏',
                subtitle: '管理右上角 5 个槽位按钮（添加 / 移除 / 排序）',
                onTap: () => PlayerBottomPanelNavigator.of(panelContext).push(
                  PlayerPanelPage(
                    title: '编辑控制栏',
                    body: const PortraitEditControlPanel(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PlayerPanelPage? _panelPageFor(PlayerTopAction action) {
    switch (action) {
      case PlayerTopAction.aspect:
        return _fitPanelPage();
      case PlayerTopAction.loop:
        return _loopPanelPage();
      default:
        return null;
    }
  }

  void _handleSlotAction(PlayerTopAction action) {
    final page = _panelPageFor(action);
    if (page != null) {
      _openBottomPanel(page);
      return;
    }
    switch (action) {
      case PlayerTopAction.aspect:
      case PlayerTopAction.loop:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.subtitle:
      case PlayerTopAction.danmaku:
      case PlayerTopAction.audio:
      case PlayerTopAction.listen:
      case PlayerTopAction.equalizer:
      case PlayerTopAction.decode:
      case PlayerTopAction.introOutro:
        if (!action.implemented) _showComingSoon(action.label);
      case PlayerTopAction.pip:
        break;
    }
  }

  void _handlePanelAction(BuildContext panelContext, PlayerTopAction action) {
    final page = _panelPageFor(action);
    if (page != null) {
      PlayerBottomPanelNavigator.of(panelContext).push(page);
      return;
    }
    switch (action) {
      case PlayerTopAction.aspect:
      case PlayerTopAction.loop:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.subtitle:
      case PlayerTopAction.danmaku:
      case PlayerTopAction.audio:
      case PlayerTopAction.listen:
      case PlayerTopAction.equalizer:
      case PlayerTopAction.decode:
      case PlayerTopAction.introOutro:
        if (!action.implemented) _showComingSoon(action.label);
      case PlayerTopAction.pip:
        break;
    }
  }

  Future<void> _openBottomPanel(PlayerPanelPage page) async {
    _hideTimer?.cancel();
    await showPlayerBottomPanel(context, pages: [page]);
    _resetHideTimer();
  }

  Future<void> _openMorePanel() async {
    _hideTimer?.cancel();
    await showPlayerBottomPanel(
      context,
      pages: [PlayerPanelPage(title: '控制栏', body: _buildMorePanel())],
    );
    _resetHideTimer();
  }

  void _showComingSoon(String name) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「$name」功能即将上线'),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── 退出与进度 ──────────────────────────────────────────

  /// 退出竖屏页（返回横屏播放页，工作.md 第 17 点「选择屏幕」）：
  /// 只保存进度并 pop——播放器/设备状态/方向/系统 UI 由横屏页统一持有与恢复，
  /// **音频零中断**（共享播放器从未停止）。
  Future<void> _exitPlayer() async {
    _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  /// 记录播放进度（播了一部分才记，避免污染"没看过的视频"）
  void _saveProgress() {
    if (_position.inMilliseconds > 0 &&
        _duration.inMilliseconds > 0 &&
        _position < _duration) {
      PlaybackProgressService.instance.save(_path, _position);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _indicatorHideTimer?.cancel();
    _speedBarTimer?.cancel();
    _swipeSeekClearTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _speedNotifier.dispose();
    _saveProgress();
    // 注意：不 dispose 播放器/控制器、不恢复设备状态——横屏页持有
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inMilliseconds);

  /// 时间文本：「已播放/总时长」⇄「已播放/剩余时长」（点击切换）
  String get _timeText {
    final pos = _dragPosition ?? _position;
    final total = _duration;
    if (_showRemaining && total > Duration.zero) {
      return '${_fmt(pos)} / -${_fmt(total - pos)}';
    }
    return '${_fmt(pos)} / ${_fmt(total)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitPlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            _viewportWidth = constraints.maxWidth;
            _viewportHeight = constraints.maxHeight;
            return Stack(
              children: [
                // 视频画面（与横屏同一 VideoController，同一路画面；
                // Android 支持多 Video 挂同一 controller）
                Positioned.fill(
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: _settings.videoFit.boxFit,
                    aspectRatio: _settings.videoFit.aspectRatio,
                  ),
                ),
                // 手势层：单击显隐控制层 / 双击按设置 / 长按倍速 /
                // 单指滑动（音量·亮度·水平 seek）。与横屏同一裸识别器
                // 方案（PlayerGestureLayer）；竖屏无锁定/双指缩放。
                Positioned.fill(
                  child: PlayerGestureLayer(
                    locked: false,
                    onTap: _toggleControls,
                    onDoubleTap: (pos) => _handleDoubleTap(pos.dx, width),
                    onLongPressStart: _onLongPressStart,
                    onLongPressUpdate: _onLongPressUpdate,
                    onLongPressEnd: _onLongPressEnd,
                    onSwipeStart: _onSwipeStart,
                    onVerticalSwipe: _onVerticalSwipe,
                    onHorizontalSwipe: _onHorizontalSwipe,
                    onSwipeEnd: _onSwipeEnd,
                    onSwipeCancel: () {},
                    onZoomStart: () {},
                    onZoomUpdate: (_) {},
                    onZoomEnd: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
                // 顶栏：返回 + 标题 + 槽位 + 更多（顶部下滑隐藏）
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedSlide(
                      offset: _controlsVisible
                          ? Offset.zero
                          : const Offset(0, -1),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: PortraitPlayerTopBar(
                          title: _title,
                          onBack: _exitPlayer,
                          onMore: _openMorePanel,
                          onActionTap: _handleSlotAction,
                        ),
                      ),
                    ),
                  ),
                ),
                // 中央控制簇：快退 / 播放暂停 / 快进（淡入淡出）
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: PlayerCenterCluster(
                          seekSeconds: _settings.seekSeconds,
                          playing: _playing,
                          onSeekBackward: () => _seekBy(-_settings.seekSeconds),
                          onSeekForward: () => _seekBy(_settings.seekSeconds),
                          onTogglePlay: _togglePlay,
                        ),
                      ),
                    ),
                  ),
                ),
                // 底栏：进度条 + 下一集 + 时间 + 倍速 + 超分（底部下滑隐藏）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedSlide(
                      offset: _controlsVisible ? Offset.zero : const Offset(0, 1),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: PortraitPlayerBottomBar(
                          valueMs: (_dragPosition ?? _position)
                              .inMilliseconds
                              .toDouble(),
                          maxMs: _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                          onSeekChanged: (v) {
                            setState(
                              () => _dragPosition =
                                  Duration(milliseconds: v.round()),
                            );
                            _resetHideTimer();
                          },
                          onSeekEnd: (v) {
                            _player.seek(Duration(milliseconds: v.round()));
                            setState(() => _dragPosition = null);
                            _resetHideTimer();
                          },
                          hasNext: _hasNext,
                          onNext: _playNext,
                          timeText: _timeText,
                          onTimeTap: () =>
                              setState(() => _showRemaining = !_showRemaining),
                          onSpeedTap: () => _openBottomPanel(_speedPanelPage()),
                          showSpeedButtonBackground:
                              _settings.showButtonBackground,
                          superResolutionLabel: '超分辨率',
                          onSuperResolutionTap: () =>
                              _openBottomPanel(_superResolutionPanelPage()),
                          // 「选择屏幕」：退出本页返回横屏播放页
                          // （横屏侧 await push 返回后自动恢复横屏方向并续播）
                          onScreenSwitchTap: _exitPlayer,
                          showScreenSwitchBackground:
                              _settings.showButtonBackground,
                          onPlaylistTap: _openPlaylistPanel,
                        ),
                      ),
                    ),
                  ),
                ),
                // 右侧操作（截图 / 锁定，从右侧滑入；与横屏同款灰黑圆角按钮）
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible || _locked,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: PlayerRightActions(
                          locked: _locked,
                          onScreenshot: _takeScreenshot,
                          onToggleLock: _toggleLock,
                        ),
                      ),
                    ),
                  ),
                ),
                // 锁定状态：左右两侧滑入解锁按钮（单击屏幕可呼出/隐藏）
                if (_locked && _unlockVisible) ...[
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _PortraitUnlockButton(onTap: _unlock),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _PortraitUnlockButton(onTap: _unlock),
                    ),
                  ),
                ],
                // 音量/亮度手势指示器：音量在左侧、亮度在右侧（对称），
                // kazumi 风格：从屏幕边缘滑入 + 淡入 + 缩放。
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment:
                          (_indicatorKind ?? GestureIndicatorKind.volume) ==
                              GestureIndicatorKind.volume
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: (_indicatorKind ??
                                      GestureIndicatorKind.volume) ==
                                  GestureIndicatorKind.volume
                              ? 32
                              : 0,
                          right: (_indicatorKind ??
                                      GestureIndicatorKind.volume) ==
                                  GestureIndicatorKind.brightness
                              ? 32
                              : 0,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) {
                            final kind = child is PlayerGestureIndicator
                                ? child.kind
                                : GestureIndicatorKind.volume;
                            final fromLeft =
                                kind == GestureIndicatorKind.volume;
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(fromLeft ? -0.35 : 0.35, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.92,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: _indicator == null
                              ? const SizedBox.shrink(key: ValueKey('none'))
                              : PlayerGestureIndicator(
                                  key: ValueKey(_indicator!.kind),
                                  kind: _indicator!.kind,
                                  value: _indicator!.value,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 水平滑动 seek 预览浮层（居中）
                if (_swipeSeekData != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: PlayerSwipeSeekOverlay(
                          target: _swipeSeekData!.target,
                          delta: _swipeSeekData!.delta,
                          visible: _swipeSeekVisible,
                        ),
                      ),
                    ),
                  ),
                // 长按倍速指示器（顶部居中；含倍速条与首次使用提示）
                Positioned(
                  left: 0,
                  right: 0,
                  top: 15,
                  child: IgnorePointer(
                    child: Center(
                      child: PlayerSpeedIndicator(
                        speed: _longPressSpeed,
                        visible: _longPressing && _settings.showSpeedIndicator,
                        dynamicActive: _dynamicSpeedActive,
                        showBar: _speedBarVisible,
                        showHint: !_settings.speedHintShown,
                        presets: dynamicSpeedPresets(),
                      ),
                    ),
                  ),
                ),
                // 双击快进/快退反馈徽章（顶部居中，控制层隐藏时也显示）
                if (_seekFeedback != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 20,
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            key: ValueKey(_seekFeedback),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _seekFeedback!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 锁定状态下的解锁按钮（屏幕左右两侧各一个，与横屏同款）。
class _PortraitUnlockButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PortraitUnlockButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.lock_open, color: Colors.white, size: 22),
        tooltip: '解锁',
        onPressed: onTap,
      ),
    );
  }
}
