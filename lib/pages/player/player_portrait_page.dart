import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/audio_player_page.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/views/player_center_cluster.dart';
import 'package:moumou/pages/player/views/player_chapter_bar.dart';
import 'package:moumou/pages/player/views/player_chapter_panel.dart';
import 'package:moumou/pages/player/views/player_fit_panel.dart';
import 'package:moumou/pages/player/views/player_gesture_indicator.dart';
import 'package:moumou/pages/player/views/player_gesture_layer.dart';
import 'package:moumou/pages/player/views/player_intro_outro_panel.dart';
import 'package:moumou/pages/player/views/player_loop_panel.dart';
import 'package:moumou/pages/player/views/player_playlist_panel.dart';
import 'package:moumou/pages/player/views/player_resume_indicator.dart';
import 'package:moumou/pages/player/views/player_speed_indicator.dart';
import 'package:moumou/pages/player/views/player_speed_panel.dart';
import 'package:moumou/pages/player/views/player_status_bar.dart';
import 'package:moumou/pages/player/views/player_super_resolution_panel.dart';
import 'package:moumou/pages/player/views/player_swipe_seek_overlay.dart';
import 'package:moumou/pages/player/views/player_thumbnail_preview.dart';
import 'package:moumou/pages/player/views/player_right_actions.dart';
import 'package:moumou/pages/player/views/portrait_edit_panel.dart';
import 'package:moumou/pages/player/views/portrait_player_bottom_bar.dart';
import 'package:moumou/pages/player/views/portrait_player_top_bar.dart';
import 'package:moumou/services/chapter_tracker.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/fast_thumbnails.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/services/intro_outro_tracker.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/utils/intro_outro_skip.dart';
import 'package:moumou/utils/playback_completion.dart';
import 'package:moumou/utils/playback_restore.dart';
import 'package:moumou/utils/player_gestures.dart';
import 'package:moumou/widgets/app_frame.dart';
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

  /// 恢复进度指示器是否应在进入本页时显示（工作.md 第 3 点：
  /// 锁定竖屏/竖屏播放时横屏页已恢复进度，本页要接住并显示指示器）
  final bool initialResumeVisible;

  /// 本页指示器关闭时通知横屏页同步隐藏（避免返回横屏后指示器残留）
  final VoidCallback? onResumeDismissed;

  /// 章节状态跟踪器（横屏页创建并持有，本页只使用、不 dispose；
  /// 传 null 时自建——正常流程横屏页总会传入）
  final ChapterTracker? chapterTracker;

  /// 片头片尾状态跟踪器（横屏页创建并持有，本页只使用、不 dispose；
  /// 传 null 时自建——正常流程横屏页总会传入）
  final IntroOutroTracker? introOutroTracker;

  const PlayerPortraitPage({
    super.key,
    required this.player,
    required this.controller,
    required this.initialPath,
    required this.initialTitle,
    this.playlist,
    this.onVideoChanged,
    this.onExitPlayer,
    this.initialResumeVisible = false,
    this.onResumeDismissed,
    this.chapterTracker,
    this.introOutroTracker,
  });

  @override
  State<PlayerPortraitPage> createState() => _PlayerPortraitPageState();
}

class _PlayerPortraitPageState extends State<PlayerPortraitPage>
    with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  late String _path;
  late String _title;
  bool _playing = false;

  // ── 播放位置/时长（risk_audit #1）────────────────────────
  // 与横屏页同款：位置流高频更新只走 ValueNotifier，底栏（进度条/时间文本）
  // 用 [_progressListenable] 局部订阅只重建自身，页面级 setState 只留给
  // 低频状态（播放/暂停、控制层显隐、锁定、切集等）。
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> _dragPositionNotifier = ValueNotifier(null);

  // ── 进度条缩略图预览（与横屏页同款）─────────────────────

  /// 当前预览（frame 为 null 表示帧仍在加载，先显示占位 + 时间）
  ({FastThumbFrame? frame, Duration time})? _thumbPreview;
  double _thumbFraction = 0;

  /// 气泡可见性（拖动中 true；松手淡出后 false 再卸载）
  bool _thumbVisible = false;
  Timer? _thumbHideTimer;
  int _lastThumbBucketMs = -1;

  /// 章节监听合并：底栏（进度条标记/章节名称）+ 胶囊浮层订阅用
  late final Listenable _chapterListenable =
      Listenable.merge([_progressListenable, _chapterTracker]);

  /// 章节状态跟踪器（工作.md 章节功能）：优先共享横屏页实例
  /// （切集/位置流统一驱动），未传入时自建并绑定共享播放器
  late final ChapterTracker _chapterTracker;

  /// 片头片尾状态跟踪器（工作.md 片头片尾功能）：优先共享横屏页实例
  /// （切集/位置流统一驱动），未传入时自建
  late final IntroOutroTracker _introOutroTracker;

  Duration get _position => _positionNotifier.value;
  Duration get _duration => _durationNotifier.value;
  Duration? get _dragPosition => _dragPositionNotifier.value;

  /// 进度相关监听合并：底栏（进度条/时间文本）局部订阅用
  late final Listenable _progressListenable = Listenable.merge([
    _positionNotifier,
    _durationNotifier,
    _dragPositionNotifier,
  ]);

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

  /// 恢复进度指示器是否可见（工作.md 第 3 点）：
  /// - 进入本页时继承横屏页已完成的恢复结果（[widget.initialResumeVisible]）；
  /// - 本页内切集恢复成功后也显示（切集流程内联，v5 重写）。
  bool _resumeVisible = false;

  /// 正在恢复进度（v5 重写：切集恢复时用不透明封层盖住视频，暂停加载 +
  /// seek 都在封层下进行，用户看不到 0 时刻第一帧海报；到位后揭开 + 播放）。
  bool _restoring = false;

  /// 听视频页打开期间为 true：本页 EOF 让位给听视频页
  bool _audioActive = false;

  /// 解锁按钮显隐动画（工作.md 第 8 点：与横屏一致——锁定后从左右两侧
  /// 滑入，单击屏幕切换呼出/隐藏，解锁时滑出）
  late final AnimationController _unlockController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<Offset> _leftUnlockSlide = Tween<Offset>(
    begin: const Offset(-1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _unlockController, curve: Curves.easeInOut));
  late final Animation<Offset> _rightUnlockSlide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _unlockController, curve: Curves.easeInOut));

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
    // 章节跟踪器：共享横屏页实例（同一 Player，状态一致）；未传入时自建
    _chapterTracker = widget.chapterTracker ??
        ChapterTracker(MpvChapterSource(_player));
    // 自建兑底：正常流程横屏页总会传入已加载的共享实例；仅在直接
    // 构造本页（无传入）时自行加载一次
    if (widget.chapterTracker == null) {
      unawaited(_chapterTracker.load());
    }
    // 片头片尾跟踪器：共享横屏页实例（同一 Player，状态一致）；
    // 未传入时自建并按共享播放器当前状态初始化（正常流程不会走此分支）
    _introOutroTracker = widget.introOutroTracker ??
        IntroOutroTracker(IntroOutroSettings.instance);
    if (widget.introOutroTracker == null) {
      final pos = _player.state.position;
      if (pos > Duration.zero) {
        _introOutroTracker.markResumedPosition(pos, _player.state.duration);
      }
      _introOutroTracker.markReady();
    }
    _path = widget.initialPath;
    _title = widget.initialTitle;

    // 工作.md 第 7 点：关闭「启用播放界面动画」后，控制层/解锁按钮
    // 的进出场动画时长归零（直接出现/消失）
    if (!_settings.playerAnimations) {
      _unlockController.duration = Duration.zero;
    }

    // 从共享播放器**当前状态**初始化（media_kit 流是广播流，迟订阅不会重放
    // 当前值；暂停/静置时无新事件——必须读 state，否则位置/时长/播放态
    // 显示为 0/错误，进度条呈"已播完"样式）
    _positionNotifier.value = _player.state.position;
    _durationNotifier.value = _player.state.duration;
    _playing = _player.state.playing;

    // 工作.md 第 3 点：横屏页已完成恢复时，本页接住并显示恢复指示器
    _resumeVisible = widget.initialResumeVisible;

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
    // 位置/时长：只更新 ValueNotifier，不再整页 setState（risk_audit #1）
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) _positionNotifier.value = p;
        // 章节跟踪：当前章节/跳过片段/胶囊自动弹出窗口随位置推进
        _chapterTracker.onPositionChanged(p);
        // 片头片尾：听视频页打开期间让位（共享同一 Player，
        // 避免重复 seek / 切集）
        if (_audioActive) return;
        _handleIntroOutroPosition(p);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) _durationNotifier.value = d;
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
    // 锁定时单击：呼出/隐藏左右解锁按钮（与横屏一致，带滑入滑出动画）
    if (_locked) {
      if (_unlockController.status == AnimationStatus.forward ||
          _unlockController.status == AnimationStatus.completed) {
        _unlockController.reverse();
      } else {
        _unlockController.forward();
      }
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
    setState(() => _locked = !_locked);
    if (_locked) {
      // 锁定：隐藏全部控制，左右滑入解锁按钮（与横屏一致）
      _hideTimer?.cancel();
      _controlsVisible = false;
      _unlockController.forward();
    } else {
      // 解锁：解锁按钮滑出，恢复控制层（与横屏一致）
      _unlockController.reverse();
      _controlsVisible = true;
      _resetHideTimer();
    }
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

  /// 双击手势（暂停 / 左退右进 / 混合，跟随设置；锁定时拦截）
  void _handleDoubleTap(double dx, double width) {
    if (_locked) return; // 锁定状态拦截双击手势，防误触
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
    if (_locked) return; // 锁定时拦截手势（工作.md 第 8 点 bug 修复）
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
    if (_locked) return; // 锁定时拦截手势（工作.md 第 8 点 bug 修复）
    _swipeSeekStart = _position;
    _volumeAccum = 0;
    _brightnessAccum = 0;
    _hideTimer?.cancel();
  }

  void _onHorizontalSwipe(double totalDx) {
    if (_locked || _duration <= Duration.zero) return;
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
    if (_locked) return; // 锁定时拦截长按倍速（工作.md 第 8 点 bug 修复）
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
    if (start == null || !_longPressing || _locked) return;
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
  /// 保存当前进度 → open（恢复时暂停加载 + 封层 + seek，见 [openAndRestore]）
  /// → 倍速/超分 → 确认新集恢复（v5 确定性恢复，无跳转）。
  Future<void> _switchTo(String path, String name) async {
    _isSwitchingVideo = true;
    try {
      // 章节功能：先清空旧媒体的章节标记（防 open 期间旧数据闪现）
      _chapterTracker.clear();
      // 片头片尾：重置跟踪状态（open 期间位置事件不评估）
      _introOutroTracker.reset();
      await _saveProgress(forcePersist: true);
      // 新集保存进度：open 时恢复（阈值过滤见 [_resumeStartFor]，
      // 防「已看完」定位到结尾触发 EOF 连播）
      final savedForNew = _resumeStartFor(path);
      // 恢复时先盖住视频（暂停加载 + seek 都在封层下）
      if (savedForNew != null && mounted) setState(() => _restoring = true);
      final restored = await openAndRestore(
        _player,
        path,
        saved: savedForNew,
        // 倍速 + 超分在播放/seek 前完成（避免 shader 变化重置位置）
        prepare: () async {
          await _player.setRate(_speed);
          try {
            await SuperResolutionService.instance.apply(_player);
          } catch (_) {
            // 忽略：超分失败不影响播放
          }
        },
      );
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _path = path;
          _title = name;
          // 同步播放器真实状态（此时文件已加载，时长/位置已就绪）
          _positionNotifier.value = _player.state.position;
          _durationNotifier.value = _player.state.duration;
          _dragPositionNotifier.value = null;
          _clearThumbnail();
          _indicator = null;
          _swipeSeekData = null;
          _resumeVisible = false;
          _restoring = false;
        });
      }
      // 通知横屏页同步最新 path/title（共享播放器，横屏侧状态必须跟随）
      widget.onVideoChanged?.call(path, name);
      if (!mounted) return;
      if (restored && savedForNew != null) {
        _positionNotifier.value = savedForNew;
        _showResumeIndicator();
      }
      // 片头片尾：恢复点感知后标记就绪（新集从头播则直接评估）
      if (restored && savedForNew != null) {
        _introOutroTracker.markResumedPosition(
          savedForNew,
          _player.state.duration,
        );
      }
      _introOutroTracker.markReady();
      // 章节功能：切集后重新读取新媒体的章节
      unawaited(_chapterTracker.load());
    } on AssertionError {
      // 共享播放器已被销毁（横屏页已退出）：静默返回，不写假崩溃日志
      return;
    } finally {
      _isSwitchingVideo = false;
    }
    _resetHideTimer();
  }

  /// 读取保存进度并做阈值过滤（与横屏页 [_resumeStartFor] 同逻辑，
  /// Kazumi `resumedNearEnd` 思路）：无进度/≤0/已看完（≥阈值）/进度过少
  /// （<5%）→ null 从头播；时长优先用播放列表 MediaStore 的 durationMs。
  Duration? _resumeStartFor(String path) {
    Duration? listDuration;
    final list = widget.playlist;
    if (list != null) {
      for (final v in list) {
        if (v.path == path && v.durationMs > 0) {
          listDuration = Duration(milliseconds: v.durationMs);
          break;
        }
      }
    }
    final saved = PlaybackProgressService.instance.getProgress(path);
    if (saved == null || saved <= Duration.zero) return null;
    if (listDuration != null &&
        !shouldRestorePosition(
          listDuration,
          saved,
          maxRestoreRatio: _settings.watchThreshold,
        )) {
      return null;
    }
    return saved;
  }

  /// 恢复到位后显示「已恢复上次播放进度」指示器（与横屏页同款）。
  ///
  /// 同步显示（无需延迟）：[PlayerResumeIndicator] 自带进场动画形成错峰；
  /// v5 恢复改由 [openAndRestore] 确定性完成，不再需要「进入视频 2s」延迟。
  void _showResumeIndicator() {
    if (!mounted) return;
    setState(() => _resumeVisible = true);
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
    // 听视频页打开期间：completed 由听视频页处理（共享播放器）
    if (_audioActive) return;
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
      case PlayerTopAction.chapter:
        return _chapterPanelPage();
      case PlayerTopAction.introOutro:
        return _introOutroPanelPage();
      default:
        return null;
    }
  }

  /// 章节列表面板（底部弹出 [showPlayerBottomPanel]，无章节时空状态提示）
  PlayerPanelPage _chapterPanelPage() {
    return PlayerPanelPage(
      title: '章节',
      body: PlayerChapterPanel(
        tracker: _chapterTracker,
        onSelect: (chapter) => _chapterTracker.seekToChapter(chapter),
      ),
    );
  }

  /// 片头片尾设置面板（底部弹出，顶栏槽位/「更多」共用）
  PlayerPanelPage _introOutroPanelPage() {
    return PlayerPanelPage(
      title: '片头片尾',
      body: PlayerIntroOutroPanel(
        positionListenable: _positionNotifier,
        durationListenable: _durationNotifier,
      ),
    );
  }

  /// 片头片尾自动跳过：位置流每次更新调用（听视频页打开期间让位，
  /// 见位置流订阅处的门控）。与横屏页 [_handleIntroOutroPosition] 同款。
  void _handleIntroOutroPosition(Duration p) {
    final action = _introOutroTracker.onPositionChanged(
      p,
      _durationNotifier.value,
      hasNext: _hasNext,
    );
    switch (action) {
      case IntroOutroAction.none:
        break;
      case IntroOutroAction.skipIntro:
        final s = IntroOutroSettings.instance;
        _player.seek(Duration(seconds: s.introSeconds));
        _toast('已跳过片头');
      case IntroOutroAction.nextEpisode:
        _toast('已跳过片尾');
        _playNext();
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
      case PlayerTopAction.chapter:
      case PlayerTopAction.introOutro:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.subtitle:
      case PlayerTopAction.danmaku:
      case PlayerTopAction.audio:
      case PlayerTopAction.equalizer:
      case PlayerTopAction.decode:
        if (!action.implemented) _showComingSoon(action.label);
      case PlayerTopAction.listen:
        _openAudioPlayer();
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
      case PlayerTopAction.chapter:
      case PlayerTopAction.introOutro:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.subtitle:
      case PlayerTopAction.danmaku:
      case PlayerTopAction.audio:
      case PlayerTopAction.equalizer:
      case PlayerTopAction.decode:
        if (!action.implemented) _showComingSoon(action.label);
      case PlayerTopAction.listen:
        // 先关闭「更多」面板再进入听视频（§4.5：不叠加第二个面板/弹窗）
        Navigator.of(panelContext).pop();
        _openAudioPlayer();
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
      pages: [PlayerPanelPage(title: '更多', body: _buildMorePanel())],
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
    await _saveProgress(forcePersist: true);
    if (mounted) Navigator.of(context).pop();
  }

  /// 顶栏返回 / 系统返回（工作.md 第 4 点 bug 修复）：
  /// 竖屏模式下返回应**直接退出播放**（先关本页，再退出横屏播放页回到列表），
  /// 而不是回到横屏再退一次。走横屏页的 [_exitWithPortrait]（onExitPlayer）。
  Future<void> _backExit() async {
    await _saveProgress(forcePersist: true);
    final exit = widget.onExitPlayer;
    if (exit != null) {
      exit();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 关闭本页恢复指示器，并通知横屏页同步隐藏（返回横屏后不残留）
  void _dismissResume() {
    if (!mounted) return;
    setState(() => _resumeVisible = false);
    widget.onResumeDismissed?.call();
  }

  // ── 进度条缩略图预览（与横屏页同款实现）────────────────

  /// 拖动进度条时请求对应时刻的画面。
  ///
  /// 两级策略（快速拖动也能即时出图）：
  /// 1. 先查内存缓存中的「最近已解码帧」——命中即秒显（时间胶囊仍显示
  ///    拖动位置，画面是最近帧，精确帧到了再替换）；
  /// 2. 无覆盖时显示加载占位，再走精确解码（FFmpeg 快速引擎 ~85ms）。
  void _requestThumbnail(int ms) {
    if (!_settings.showThumbnailPreview) return;
    if (_duration <= Duration.zero || _path.isEmpty) return;
    // 新拖动开始：终止空闲预取（预取与新请求共享单飞队列，无需其他处理）
    _cancelThumbPrefetch();
    final clamped = ms.clamp(0, _duration.inMilliseconds);
    final bucket = (clamped ~/ 1000) * 1000;
    if (bucket == _lastThumbBucketMs) return;
    _lastThumbBucketMs = bucket;
    _thumbFraction = _duration.inMilliseconds > 0
        ? clamped / _duration.inMilliseconds
        : 0;

    // 1) 最近已解码帧即时显示（同一区域来回拖动零解码）
    final nearest = DeviceServices.peekNearestFrame(
      _path,
      bucket,
      maxGapMs: 10000,
    );
    if (nearest != null) {
      setState(() {
        _thumbPreview =
            (frame: nearest.frame, time: Duration(milliseconds: bucket));
        _thumbVisible = true;
      });
      // 精确桶已缓存或已跳过，则无需再取
      if (DeviceServices.peekFrame(_path, bucket) != null) return;
      _fetchThumbnail(bucket);
      return;
    }

    // 2) 无覆盖：占位 + 精确解码
    setState(() {
      _thumbPreview = (frame: null, time: Duration(milliseconds: bucket));
      _thumbVisible = true;
    });
    _fetchThumbnail(bucket);
  }

  /// 精确桶异步取帧（失败/过期自动丢弃）
  void _fetchThumbnail(int bucket) {
    DeviceServices.getVideoFrameAt(_path, bucket).then((frame) {
      if (!mounted || frame == null) return;
      // 已拖到别的秒：丢弃过期帧（_lastThumbBucketMs 只记录最新请求）
      if (_lastThumbBucketMs != bucket) return;
      setState(() {
        _thumbPreview = (frame: frame, time: Duration(milliseconds: bucket));
      });
    });
  }

  /// 松手：气泡淡出（150ms 动画）后再卸载，避免硬切闪烁
  void _hideThumbPreview() {
    _thumbHideTimer?.cancel();
    if (_thumbPreview == null) return;
    setState(() => _thumbVisible = false);
    _thumbHideTimer = Timer(const Duration(milliseconds: 250), () {
      // 期间又开始了新一轮拖动（_thumbVisible 被置回 true）则不清
      if (!mounted || _thumbVisible) return;
      setState(() {
        _thumbPreview = null;
        _lastThumbBucketMs = -1;
      });
    });
  }

  /// 立即清空缩略图预览（切集/退出时调用，需处于 setState 内或随后触发重建）
  void _clearThumbnail() {
    _thumbHideTimer?.cancel();
    _cancelThumbPrefetch();
    _thumbPreview = null;
    _thumbVisible = false;
    _lastThumbBucketMs = -1;
  }

  // ── 空闲预取邻近秒桶（对齐 mpvRx：松手停住后后台补附近帧）──

  Timer? _thumbPrefetchTimer;
  int _thumbPrefetchGen = 0;

  void _cancelThumbPrefetch() {
    _thumbPrefetchTimer?.cancel();
    _thumbPrefetchTimer = null;
    _thumbPrefetchGen++;
  }

  /// 松手停住 350ms 后，把 [bucketMs] 附近 ±1/±2/±3 秒的秒桶串行补进
  /// 内存缓存（每帧 ~85ms，共 6 帧）——再次拖到附近秒显。
  /// 用户重新拖动（onChanged 会取消）/ 切集 / 退出立即终止；
  /// 与实时抓帧共享单飞队列与缓存去重，不重复解码、不抢优先级
  /// （新拖动请求会顶掉排队中的预取）。
  void _scheduleThumbPrefetch(int bucketMs) {
    _cancelThumbPrefetch();
    final gen = _thumbPrefetchGen;
    _thumbPrefetchTimer = Timer(const Duration(milliseconds: 350), () async {
      for (final delta in const [1000, -1000, 2000, -2000, 3000, -3000]) {
        if (!mounted || gen != _thumbPrefetchGen) return;
        // 用户又开始拖动 → 立即终止
        if (_dragPosition != null) return;
        if (!_settings.showThumbnailPreview) return;
        final b = bucketMs + delta;
        if (b < 0) continue;
        if (DeviceServices.peekFrame(_path, b) != null) continue;
        await DeviceServices.getVideoFrameAt(_path, b);
      }
    });
  }

  /// 听视频（工作.md 第 10 点）：竖屏页「更多 → 听视频」进入。
  /// 共享同一 Player（音频零中断），听视频页是竖屏界面；返回后本页继续。
  Future<void> _openAudioPlayer() async {
    _hideTimer?.cancel();
    _audioActive = true;
    if (mounted) setState(() {});
    await Navigator.of(context).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: playerRouteName),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => AudioPlayerPage(
          player: _player,
          initialPath: _path,
          initialTitle: _title,
          playlist: widget.playlist,
          onVideoChanged: (path, title) {
            if (!mounted) return;
            setState(() {
              _path = path;
              _title = title;
              _positionNotifier.value = _player.state.position;
              _durationNotifier.value = _player.state.duration;
              _dragPositionNotifier.value = null;
            });
            widget.onVideoChanged?.call(path, title);
          },
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;
    _audioActive = false;
    setState(() {});
    // 听视频页可能已切集：按当前媒体状态重新初始化片头片尾跟踪
    // （位置 > 0 按恢复点处理不跳片头；新集从头播则正常评估）
    final audioPos = _player.state.position;
    if (audioPos > Duration.zero) {
      _introOutroTracker.reset();
      _introOutroTracker.markResumedPosition(
        audioPos,
        _player.state.duration,
      );
      _introOutroTracker.markReady();
    }
    // 听视频页竖屏，返回后本页保持竖屏 + 沉浸式
    _enterFullscreen();
    _resetHideTimer();
  }

  /// 记录播放进度（播了一部分才记，避免污染"没看过的视频"）。
  /// [forcePersist] = true 时强制落盘（退出/切集调用，保证重启后可恢复）。
  Future<void> _saveProgress({bool forcePersist = false}) async {
    if (_position.inMilliseconds > 0 &&
        _duration.inMilliseconds > 0 &&
        _position < _duration) {
      await PlaybackProgressService.instance.save(
        _path,
        _position,
        forcePersist: forcePersist,
      );
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _indicatorHideTimer?.cancel();
    _speedBarTimer?.cancel();
    _swipeSeekClearTimer?.cancel();
    _thumbHideTimer?.cancel();
    _cancelThumbPrefetch();
    for (final s in _subs) {
      s.cancel();
    }
    _speedNotifier.dispose();
    _unlockController.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _dragPositionNotifier.dispose();
    // 仅自建时销毁（共享实例由横屏页持有与销毁）
    if (widget.chapterTracker == null) _chapterTracker.dispose();
    _saveProgress();
    // 注意：不 dispose 播放器/控制器、不恢复设备状态——横屏页持有
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inMilliseconds);

  /// 控制层滑入动画时长（工作.md 第 7 点：关闭「启用播放界面动画」后归零）
  Duration get _controlsAnimDuration =>
      _settings.playerAnimations ? const Duration(milliseconds: 250) : Duration.zero;

  /// 控制层淡入动画时长（同上）
  Duration get _controlsFadeDuration =>
      _settings.playerAnimations ? const Duration(milliseconds: 200) : Duration.zero;

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
        // 工作.md 第 4 点：竖屏模式下返回直接退出播放
        _backExit();
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
                // Android 支持多 Video 挂同一 controller）。
                // 用 ListenableBuilder 监听设置：画面比例实时生效
                //（工作.md 第 8 点 bug 修复）
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: _settings,
                    builder: (context, _) => Video(
                      // ⚠️ key 随 fit 变化：4:3 → 自动时强制重建，
                      // 否则 Video 内部渲染纹理尺寸缓存不刷新（工作.md 第 3 点）
                      key: ValueKey('fit-${_settings.videoFit.index}'),
                      controller: _controller,
                      controls: NoVideoControls,
                      fit: _settings.videoFit.boxFit,
                      aspectRatio: _settings.videoFit.aspectRatio,
                    ),
                  ),
                ),
                // 手势层：单击显隐控制层 / 双击按设置 / 长按倍速 /
                // 单指滑动（音量·亮度·水平 seek）。与横屏同一裸识别器
                // 方案（PlayerGestureLayer）；锁定时仅放行单击（呼出/隐藏
                // 解锁按钮），其余手势全部拦截（工作.md 第 8 点 bug 修复）。
                Positioned.fill(
                  child: PlayerGestureLayer(
                    locked: _locked,
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
                // 顶栏：时间/电量信息行（工作.md 第 12 点）+ 返回 + 标题 +
                // 槽位 + 更多（顶部下滑隐藏）
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
                      duration: _controlsAnimDuration,
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: _controlsFadeDuration,
                        // 顶部渐变压暗统一放这里（信息行 + 顶栏整体一个连续
                        // 渐变，顶部最暗 → 向下淡出）；组件不再各自画渐变，
                        // 避免两段渐变拼接的暗色断层（用户反馈 v2）
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.72),
                                Colors.black.withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PlayerStatusBar(portrait: true),
                              PortraitPlayerTopBar(
                                title: _title,
                                onBack: _backExit,
                                onMore: _openMorePanel,
                                onActionTap: _handleSlotAction,
                              ),
                            ],
                          ),
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
                      duration: _controlsFadeDuration,
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
                // 底栏：进度条 + 下一集 + 时间 + 倍速 + 超分（底部下滑隐藏）。
                // 胶囊浮层贴底栏顶部，独立于底栏滑出动画（自动弹出期间
                // 控制层隐藏也可见）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 跳过胶囊（工作.md 第 4 点）：进入 OP/ED 等片段自动
                      // 弹出（5 秒倒计时自动消失）；控制层可见且仍在片段内
                      // 时常驻；回拖进片段可重复触发
                      ListenableBuilder(
                        listenable: _chapterTracker,
                        builder: (context, _) {
                          final seg = _chapterTracker.activeSegment;
                          final visible = seg != null &&
                              !_locked &&
                              (_chapterTracker.autoChipVisible ||
                                  _controlsVisible);
                          return AnimatedOpacity(
                            opacity: visible ? 1 : 0,
                            duration: _controlsFadeDuration,
                            child: IgnorePointer(
                              ignoring: !visible,
                              child: seg == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        left: kPlayerLeftInset,
                                        bottom: 8,
                                      ),
                                      child: ChapterSkipChip(
                                        type: seg.type,
                                        onTap: () =>
                                            _chapterTracker.skipActiveSegment(),
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: AnimatedSlide(
                          offset: _controlsVisible
                              ? Offset.zero
                              : const Offset(0, 1),
                          duration: _controlsAnimDuration,
                          curve: Curves.easeInOut,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: _controlsFadeDuration,
                            // 局部订阅进度 + 章节：位置/时长/章节变化只重建
                            // 底栏（进度条 + 时间文本 + 章节标记），不重建整页
                            //（risk_audit #1）
                            child: ListenableBuilder(
                              listenable: _chapterListenable,
                              builder: (context, _) => PortraitPlayerBottomBar(
                                valueMs: (_dragPosition ?? _position)
                                    .inMilliseconds
                                    .toDouble(),
                                maxMs: _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1.0,
                                onSeekChanged: (v) {
                                  _dragPositionNotifier.value =
                                      Duration(milliseconds: v.round());
                                  _requestThumbnail(v.round());
                                  _resetHideTimer();
                                },
                                onSeekEnd: (v) {
                                  _player.seek(
                                      Duration(milliseconds: v.round()));
                                  _dragPositionNotifier.value = null;
                                  _hideThumbPreview();
                                  // 空闲后预取邻近秒桶，下次拖到附近秒显
                                  _scheduleThumbPrefetch(
                                      (v.round() ~/ 1000) * 1000);
                                  _resetHideTimer();
                                },
                                hasNext: _hasNext,
                                onNext: _playNext,
                                timeText: _timeText,
                                onTimeTap: () => setState(
                                    () => _showRemaining = !_showRemaining),
                                onSpeedTap: () =>
                                    _openBottomPanel(_speedPanelPage()),
                                showSpeedButtonBackground:
                                    _settings.showButtonBackground,
                                superResolutionLabel: '超分辨率',
                                onSuperResolutionTap: () => _openBottomPanel(
                                    _superResolutionPanelPage()),
                                // 「选择屏幕」：退出本页返回横屏播放页
                                // （横屏侧 await push 返回后自动恢复横屏方向并续播）
                                onScreenSwitchTap: _exitPlayer,
                                showScreenSwitchBackground:
                                    _settings.showButtonBackground,
                                // 工作.md 第 4 点：列表按钮背景与倍速按钮同开关
                                showListButtonBackground:
                                    _settings.showButtonBackground,
                                onPlaylistTap: _openPlaylistPanel,
                                // 章节功能（工作.md）：「显示章节进度条」开关
                                // 只控制进度条上的圆点与章节名称行；
                                // 跳过色段与胶囊属于动漫跳过，强制开启不受开关影响
                                chapters: _settings.showChapterProgress
                                    ? _chapterTracker.chapters
                                    : const [],
                                skipSegments: _chapterTracker.skipSegments,
                                currentChapterName:
                                    _settings.showChapterProgress
                                        ? _chapterTracker.currentChapterTitle
                                        : null,
                                onChapterTap: () =>
                                    _openBottomPanel(_chapterPanelPage()),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 进度条拖动缩略图预览（进度条上方跟随拖动位置；松手淡出后再卸载）。
                // bottom = 进度条 40 + 操作行 50 + 6px 余量 + 底部安全区（手势条），
                // 气泡底缘刚好贴进度条上方（有章节名称行时会叠入名称行，
                // 与横屏页同款行为）。
                if (_thumbPreview != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96 + MediaQuery.of(context).padding.bottom,
                    child: PlayerThumbnailPreview(
                      frame: _thumbPreview!.frame,
                      time: _thumbPreview!.time,
                      fraction: _thumbFraction,
                      visible: _thumbVisible,
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
                      duration: _controlsFadeDuration,
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
                // 锁定状态：左右两侧滑入解锁按钮（工作.md 第 8 点：
                // 进出场动画与横屏一致——滑入滑出，单击屏幕可呼出/隐藏）
                if (_locked)
                  SlideTransition(
                    position: _leftUnlockSlide,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _PortraitUnlockButton(onTap: _unlock),
                      ),
                    ),
                  ),
                if (_locked)
                  SlideTransition(
                    position: _rightUnlockSlide,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _PortraitUnlockButton(onTap: _unlock),
                      ),
                    ),
                  ),
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
                // 恢复进度指示器（工作.md 第 3 点：竖屏/锁定竖屏也要显示；
                // 竖屏顶栏（信息行 + 返回/标题/槽位）较高，指示器放其下方）
                if (_resumeVisible)
                  Positioned(
                    // 稳定 key：拖动进度条时缩略图气泡（前一个条件 Positioned）
                    // 会插入/移出 Stack children，无 key 兄弟项按索引错位匹配
                    // 会重建 State → 指示器进场动画重播（与横屏同款修复）
                    key: const ValueKey('resumeIndicator'),
                    left: 0,
                    right: 0,
                    top: 100,
                    child: IgnorePointer(
                      child: Center(
                        child: PlayerResumeIndicator(
                          onRestart: () {
                            _player.seek(Duration.zero);
                            _player.play();
                            _dismissResume();
                          },
                          onClose: _dismissResume,
                        ),
                      ),
                    ),
                  ),
                // 恢复进度封层（z 序最顶）：切集恢复时盖住视频，暂停加载 +
                // seek 期间用户看不到 0 时刻第一帧海报；到位后揭开 + 播放。
                if (_restoring)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white24),
                          ),
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
