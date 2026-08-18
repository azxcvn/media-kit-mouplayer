import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/views/player_bottom_bar.dart';
import 'package:moumou/pages/player/views/player_center_cluster.dart';
import 'package:moumou/pages/player/views/player_fit_panel.dart';
import 'package:moumou/pages/player/views/player_gesture_indicator.dart';
import 'package:moumou/pages/player/views/player_gesture_layer.dart';
import 'package:moumou/pages/player/views/player_right_actions.dart';
import 'package:moumou/pages/player/views/player_speed_indicator.dart';
import 'package:moumou/pages/player/views/player_speed_panel.dart';
import 'package:moumou/pages/player/views/player_super_resolution_panel.dart';
import 'package:moumou/pages/player/views/player_swipe_seek_overlay.dart';
import 'package:moumou/pages/player/views/player_thumbnail_preview.dart';
import 'package:moumou/pages/player/views/player_top_bar.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/services/thumbnail_preload_service.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/utils/player_gestures.dart';
import 'package:moumou/widgets/player_panel.dart';
import 'package:saver_gallery/saver_gallery.dart';

/// 播放页：默认横屏播放，自定义现代化控制 UI。
///
/// - 中央三键簇：快退 / 播放暂停 / 快进；
/// - 双击手势可自定义（暂停 / 左退右进 / 混合）；
/// - 右上角固定「更多」按钮 → 右侧面板（动作列表 + 编辑控制栏）；
/// - 倍速等二级设置统一走右侧滑入面板（[showPlayerPanel]）。
///
/// [playlist] 为兄弟视频列表（用于「下一集」，null 时按钮置灰）。
class PlayerPage extends StatefulWidget {
  final String path;
  final String title;
  final List<VideoFile>? playlist;

  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.playlist,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  late String _path;
  late String _title;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  double _speed = 1.0;

  /// 控制层显隐动画（Kazumi 风格：顶部下落 / 底部上升 / 右侧滑入 / 中央淡入）
  late final AnimationController _controlsController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1, // 初始显示
  );
  late final Animation<Offset> _topSlide = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controlsController, curve: Curves.easeInOut));
  late final Animation<Offset> _bottomSlide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controlsController, curve: Curves.easeInOut));
  late final Animation<Offset> _rightSlide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controlsController, curve: Curves.easeInOut));

  /// 控制层是否锁定（锁定后隐藏全部控制；左右两侧出现解锁按钮，
  /// 单击屏幕可呼出/隐藏解锁按钮）
  bool _locked = false;

  /// 解锁按钮显隐动画（锁定后从左右两侧滑入，单击屏幕切换呼出/隐藏）
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

  /// 实际倍速的监听器：倍速面板（独立弹窗路由）通过它实时刷新
  final ValueNotifier<double> _speedNotifier = ValueNotifier(1.0);

  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  /// 当前视口尺寸（手势计算用，build 时更新）
  double _viewportWidth = 0;
  double _viewportHeight = 0;

  // ── 音量 / 亮度 ────────────────────────────────────────

  /// 当前应用音量（0 – 100，进入时同步自系统音量）
  double _volume = 50;

  /// 进入播放前的系统音量（退出时按设置写回或恢复）
  double? _initialSystemVolume;

  /// 当前亮度（0 – 1，窗口亮度）
  double _brightness = 1.0;

  /// 音量/亮度浮点累加器（小步长滑动不丢失，参考 kt 项目）
  double _volumeAccum = 0;
  double _brightnessAccum = 0;

  /// 手势指示器（音量/亮度共用，2 秒无操作自动隐藏）
  ({GestureIndicatorKind kind, double value})? _indicator;

  /// 最近一次显示的指示器类型：退场动画期间 [_indicator] 已置 null，
  /// 但布局位置（左/右）必须沿用旧类型，否则亮度退场会跳到左侧
  GestureIndicatorKind? _indicatorKind;
  Timer? _indicatorHideTimer;

  // ── 长按倍速 ──────────────────────────────────────────

  bool _longPressing = false;
  double? _speedBeforeLongPress;

  /// 当前长按倍速（初始为设置值，左右滑动后为动态档位）
  double _longPressSpeed = 2.0;

  /// 长按按下位置（动态调速的横向位移基准）
  Offset? _longPressStartPos;

  /// 动态调速起始档位索引（按下时确定，避免调速过程中漂移）
  int _dynamicStartIndex = 0;
  bool _dynamicSpeedActive = false;
  bool _speedBarVisible = false;
  Timer? _speedBarTimer;

  // ── 水平滑动 seek ─────────────────────────────────────

  Duration _swipeSeekStart = Duration.zero;
  ({Duration target, Duration delta})? _swipeSeekData;
  bool _swipeSeekVisible = false;
  Timer? _swipeSeekClearTimer;
  DateTime? _lastSwipeSeekTime;

  // ── 双指缩放 / 平移 ───────────────────────────────────

  double _zoomScale = 1.0;
  Offset _zoomOffset = Offset.zero;
  double? _zoomStartScale;

  // ── 进度条缩略图预览 ──────────────────────────────────

  /// 当前预览（bytes 为 null 表示帧仍在加载，先显示占位 + 时间）
  ({Uint8List? bytes, Duration time})? _thumbPreview;
  double _thumbFraction = 0;
  int _lastThumbBucketMs = -1;

  /// 全片缩略图后台预热（快速拖动也能即时显示最近帧）
  final ThumbnailPreloadService _preload = ThumbnailPreloadService();

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
    _path = widget.path;
    _title = widget.title;
    _player = Player();
    _controller = VideoController(_player);

    // 倍速记忆：启用时恢复上次倍速
    _speed = _settings.rememberSpeed ? _settings.lastSpeed : 1.0;
    _speedNotifier.value = _speed;
    // 进入播放器：未开启记忆时本次会话从「关闭/均衡」开始超分
    // （退出播放/重启后自动回到默认关闭，记忆开启才恢复上次设置）
    SuperResolutionService.instance.enterPlayer();
    // 同步系统音量/亮度作为本次会话起点（音量从手机当前音量开始）
    _initDeviceState();
    _openAndSetRate();

    // 默认强制横屏 + 沉浸式全屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterFullscreen();

    // 横屏旋转与路由转场是异步的，完成后系统栏可能被临时恢复显示；
    // 在转场后再次确认沉浸式，并延迟重设一次，确保状态栏不再露出
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
          if (!p && !_locked) {
            _controlsVisible = true;
            _controlsController.forward();
          }
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
        // 缩略图预热不再进入播放即触发：改为「用户第一次拖动进度条时」
        // 才从当前位置向外预热（见 _requestThumbnail），省去不拖动用户的
        // 后台解码与缓存占用。
      }),
    );

    _resetHideTimer();
  }

  /// 打开媒体后再设置倍速（media_kit 在加载完成后生效）；
  /// 随后按当前超分模式重放着色器（切换文件后 mpv 的 glsl-shaders 需重新确认）
  Future<void> _openAndSetRate() async {
    await _player.open(Media(_path));
    _player.setRate(_speed);
    await SuperResolutionService.instance.apply(_player);
  }

  /// 读取系统音量/亮度作为本次会话起点：
  /// - 音量：以手机当前系统音量为播放音量起点（如 20%）；
  /// - 亮度：读系统亮度并应用到窗口（kt/mpvEx 做法），保证指示器数值
  ///   与屏幕实际亮度一致；退出时恢复 -1 交还系统控制（自动亮度恢复）。
  Future<void> _initDeviceState() async {
    final vol = await DeviceServices.getSystemVolume();
    _initialSystemVolume = vol;
    if (vol != null) {
      _volume = vol;
      await _player.setVolume(vol);
    } else {
      // 读取失败：用中间值兜底
      _volume = 50;
      await _player.setVolume(50);
    }
    final brightness = await DeviceServices.getBrightness();
    if (brightness != null) {
      _brightness = brightness;
      // 锁到窗口，使屏幕显示与指示器一致（播放期间亮度不随自动亮度漂移）
      await DeviceServices.setWindowBrightness(brightness);
    }
    if (mounted) setState(() {});
  }

  /// 退出播放时恢复设备状态：
  /// - 亮度：恢复 -1（交还系统控制 = 进入播放前的状态）；
  /// - 音量：开启「保存到系统」→ 写回当前播放音量；
  ///   关闭 → 恢复进入前的系统音量。
  Future<void> _restoreDeviceState() async {
    await DeviceServices.setWindowBrightness(null);
    final target = _settings.saveVolumeToSystem
        ? _volume
        : (_initialSystemVolume ?? _volume);
    await DeviceServices.setSystemVolume(target);
  }

  /// 进入沉浸式全屏：隐藏状态栏/导航栏，并把系统栏设为透明
  /// （即使系统栏短暂出现，也是透明的，不会露出浅色背景）
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
        _controlsController.reverse();
      }
    });
  }

  void _toggleControls() {
    // 锁定时单击：呼出/隐藏左右解锁按钮（带滑入滑出动画）
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
      _controlsController.forward();
      _resetHideTimer();
    } else {
      _controlsController.reverse();
      _hideTimer?.cancel();
    }
  }

  // ── 锁定 / 解锁 ─────────────────────────────────────────

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (_locked) {
      // 锁定：隐藏全部控制，左右滑入解锁按钮
      _hideTimer?.cancel();
      if (_controlsVisible) {
        _controlsVisible = false;
        _controlsController.reverse();
      }
      _unlockController.forward();
    } else {
      // 解锁：解锁按钮滑出，恢复控制层
      _unlockController.reverse();
      _controlsVisible = true;
      _controlsController.forward();
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

  Future<void> _togglePlay() async {
    await _player.playOrPause();
    _resetHideTimer();
  }

  // ── 手势 ────────────────────────────────────────────────

  void _handleDoubleTap(double dx, double width) {
    if (_locked) return; // 锁定状态拦截双击手势，防误触
    final gesture = classifyDoubleTap(
      dx,
      width,
      _settings.doubleTapMode,
    );
    switch (gesture) {
      case DoubleTapGesture.pauseToggle:
        _togglePlay();
      case DoubleTapGesture.seekBackward:
        _seekBy(-_settings.seekSeconds);
      case DoubleTapGesture.seekForward:
        _seekBy(_settings.seekSeconds);
    }
  }

  // ── 音量 / 亮度手势（左侧亮度，右侧音量）───────────────

  /// 指示器显隐：显示 [kind] 对应指示器，2 秒无操作自动隐藏
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
    if (_locked) return;
    if (_viewportHeight <= 0) return;
    if (isLeftHalf) {
      // 左侧：亮度（只调窗口亮度，不动系统；退出恢复）
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
      // 右侧：音量（只调播放器音量，退出时按设置写回/恢复系统）
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
          _player.setVolume(newV);
          _showIndicator(GestureIndicatorKind.volume, newV);
        }
      }
    }
  }

  // ── 水平滑动 seek ──────────────────────────────────────

  void _onSwipeStart() {
    if (_locked) return;
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
    // 实时 seek 节流：两次操作至少间隔 40ms，避免拖动过快卡顿
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
    // 数据保留 250ms 让浮层淡出
    _swipeSeekClearTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _swipeSeekData = null);
    });
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  /// 单指滑动被双指手势打断（意图改为缩放）：撤销已发生的 seek，
  /// 避免「缩放时误触发左右滑动」
  void _onSwipeCancel() {
    if (_swipeSeekData != null && _duration > Duration.zero) {
      _player.seek(_swipeSeekStart);
    }
    _swipeSeekVisible = false;
    _swipeSeekClearTimer?.cancel();
    _lastSwipeSeekTime = null;
    _swipeSeekData = null;
    if (mounted) setState(() {});
  }

  // ── 长按倍速 ───────────────────────────────────────────

  void _onLongPressStart(Offset pos) {
    if (_locked) return;
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
    _hideTimer?.cancel(); // 长按期间不自动隐藏控制层
    if (mounted) setState(() {});
  }

  /// 长按期间左右滑动：临时调整长按倍速（1.5 – 4.0，间隔 0.5，离散）
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
    // 首次完成「长按 + 左右滑动」：永久标记，后续不再出现提示
    _settings.markSpeedHintShown();
    // 停在某档位 3 秒后自动隐藏倍速条
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
    // 恢复长按前的倍速
    final restore = _speedBeforeLongPress ?? _speed;
    _speedBeforeLongPress = null;
    _longPressStartPos = null;
    _player.setRate(restore);
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  // ── 双指缩放 / 平移 ────────────────────────────────────

  void _onZoomStart() {
    if (_locked) return;
    _zoomStartScale = _zoomScale;
    _hideTimer?.cancel();
  }

  void _onZoomUpdate(ScaleUpdateDetails d) {
    if (_locked || _zoomStartScale == null) return;
    final minScale = _settings.enableShrinkVideo ? 0.75 : 1.0;
    // 双指最大放大倍率：4.0（原 2.0，用户要求增加；最小仍受设置控制）
    final newScale = (_zoomStartScale! * d.scale).clamp(minScale, 4.0);
    final ratio = newScale / _zoomScale;
    final focal = d.localFocalPoint;
    // 以双指焦点为中心缩放，再跟随焦点移动平移（PiliPlus 同款）
    _zoomOffset = focal - (focal - _zoomOffset) * ratio;
    _zoomScale = newScale;
    _zoomOffset += d.focalPointDelta;
    _clampZoomOffset();
    if (mounted) setState(() {});
  }

  void _onZoomEnd() {
    _zoomStartScale = null;
    if (_zoomScale == 1.0) _zoomOffset = Offset.zero;
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  /// 缩放平移边界：画面不能露出黑边（缩放 1 倍时归中）
  void _clampZoomOffset() {
    final w = _viewportWidth;
    final h = _viewportHeight;
    if (w <= 0 || h <= 0) return;
    final maxDx = ((_zoomScale - 1).abs() * w) / 2;
    final maxDy = ((_zoomScale - 1).abs() * h) / 2;
    _zoomOffset = Offset(
      _zoomOffset.dx.clamp(-maxDx, maxDx),
      _zoomOffset.dy.clamp(-maxDy, maxDy),
    );
  }

  /// 画面缩放矩阵：以视口中心为缩放原点，再按 [_zoomOffset] 平移
  Matrix4 _zoomMatrix() {
    final w = _viewportWidth / 2;
    final h = _viewportHeight / 2;
    return Matrix4.identity()
      ..translateByDouble(_zoomOffset.dx + w, _zoomOffset.dy + h, 0, 1)
      ..scaleByDouble(_zoomScale, _zoomScale, _zoomScale, 1)
      ..translateByDouble(-w, -h, 0, 1);
  }

  void _resetZoom() {
    _zoomScale = 1.0;
    _zoomOffset = Offset.zero;
    if (mounted) setState(() {});
  }

  // ── 进度条缩略图预览 ───────────────────────────────────

  /// 拖动进度条时请求对应时刻的画面。
  ///
  /// 两级策略（快速拖动也能即时出图）：
  /// 1. 先查内存缓存中的「最近预生成帧」——命中即秒显（时间胶囊仍显示
  ///    拖动位置，画面是最近采样点，精确帧到了再替换）；
  /// 2. 无覆盖时显示加载占位，再走精确解码（与预生成共享缓存/去重）。
  void _requestThumbnail(int ms) {
    if (!_settings.showThumbnailPreview) return;
    if (_duration <= Duration.zero || _path.isEmpty) return;
    final clamped = ms.clamp(0, _duration.inMilliseconds);
    final bucket = (clamped ~/ 1000) * 1000;
    if (bucket == _lastThumbBucketMs) return;
    _lastThumbBucketMs = bucket;
    _thumbFraction = _duration.inMilliseconds > 0
        ? clamped / _duration.inMilliseconds
        : 0;

    // 拖动进度条才启动整段缩略图后台预热（从当前位置向外扩散，先近后远）。
    // 只有真正拖动过的用户才产生后台解码与磁盘缓存开销。
    if (!_preload.isActiveFor(_path)) {
      _preload.start(
        _path,
        _duration.inMilliseconds,
        fromMs: clamped,
      );
    }

    // 1) 最近预生成帧即时显示
    final nearest = DeviceServices.peekNearestFrame(
      _path,
      bucket,
      maxGapMs: ThumbnailPreloadService.intervalFor(_duration),
    );
    if (nearest != null) {
      setState(() {
        _thumbPreview =
            (bytes: nearest.bytes, time: Duration(milliseconds: bucket));
      });
      // 精确桶已缓存或已跳过，则无需再取
      if (DeviceServices.peekFrame(_path, bucket) != null) return;
      _fetchThumbnail(bucket);
      return;
    }

    // 2) 无覆盖：占位 + 精确解码
    setState(() {
      _thumbPreview = (bytes: null, time: Duration(milliseconds: bucket));
    });
    _fetchThumbnail(bucket);
  }

  /// 精确桶异步取帧（失败/过期自动丢弃）
  void _fetchThumbnail(int bucket) {
    DeviceServices.getVideoFrameAt(_path, bucket).then((bytes) {
      if (!mounted || bytes == null || bytes.isEmpty) return;
      // 已拖到别的秒：丢弃过期帧（_lastThumbBucketMs 只记录最新请求）
      if (_lastThumbBucketMs != bucket) return;
      setState(() {
        _thumbPreview = (bytes: bytes, time: Duration(milliseconds: bucket));
      });
    });
  }

  void _clearThumbnail() {
    _thumbPreview = null;
    _lastThumbBucketMs = -1;
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

  /// 双击快进/快退的顶部徽章反馈（控制层隐藏时也显示）
  void _showSeekFeedback(String text) {
    _seekFeedbackTimer?.cancel();
    if (mounted) setState(() => _seekFeedback = text);
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  /// 提示功能即将上线（占位入口）
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

  // ── 下一集 ──────────────────────────────────────────────

  Future<void> _playNext() async {
    final list = widget.playlist;
    if (list == null) return;
    final idx = list.indexWhere((v) => v.path == _path);
    if (idx < 0 || idx >= list.length - 1) return;
    final next = list[idx + 1];
    _saveProgress();
    await _player.open(Media(next.path));
    _player.setRate(_speed);
    // 切集后重放着色器（mpv 打开新文件时着色器链需重新确认）
    await SuperResolutionService.instance.apply(_player);
    if (mounted) {
      setState(() {
        _path = next.path;
        _title = next.name;
        _position = Duration.zero;
        _duration = Duration.zero;
        _dragPosition = null;
        _zoomScale = 1.0;
        _zoomOffset = Offset.zero;
        _indicator = null;
        _swipeSeekData = null;
        _clearThumbnail();
      });
      // 切集：取消旧视频的缩略图预热（新视频拖动进度条时才重新预热）
      _preload.cancel();
    }
    _resetHideTimer();
  }

  // ── 倍速 ────────────────────────────────────────────────

  /// 应用倍速。[remember] 为 true 时写入记忆（下次打开恢复），
  /// 临时调整传 false，避免高频写盘。
  void _setSpeed(double v, {bool remember = true}) {
    _speed = v;
    _speedNotifier.value = v; // 通知倍速面板实时刷新
    _player.setRate(v);
    if (remember) _settings.setSpeed(v);
    if (mounted) setState(() {});
  }

  // ── 右侧面板（更多 / 倍速 / 编辑控制栏）────────────────

  /// 倍速面板页（底栏倍速按钮弹出）
  PlayerPanelPage _speedPanelPage() => PlayerPanelPage(
        title: '播放倍速',
        body: PlayerSpeedPanel(
          speedListenable: _speedNotifier,
          onSpeedChanged: _setSpeed,
          onTemporaryApply: (v) => _setSpeed(v, remember: false),
          onReset: () => _setSpeed(1.0),
        ),
      );

  /// 超分面板页（底栏超分辨率按钮弹出，与倍速面板同一外壳/胶囊样式）。
  /// 面板直接驱动 [SuperResolutionService] 单例（模式/质量/记忆）。
  PlayerPanelPage _superResolutionPanelPage() => PlayerPanelPage(
        title: '超分辨率',
        body: PlayerSuperResolutionPanel(player: _player),
      );

  /// 画面比例面板页（顶栏「比例」槽位弹出，PiliPlus 同款选项）
  PlayerPanelPage _fitPanelPage() => PlayerPanelPage(
        title: '画面比例',
        body: const PlayerFitPanel(),
      );

  /// 「更多」面板主页：仅「编辑控制栏」入口（功能由用户放到槽位后使用）
  Widget _buildMorePanel() {
    // 用 Builder 取面板树内的 context：PlayerPanelNavigator.of 要求调用方
    // 位于 _PanelNavigatorScope 之下（在弹窗路由内），不能直接用 State 的 context
    // （历史 bug：of() 断言 scope == null，编辑控制栏点击无反应）。
    return Builder(
      builder: (panelContext) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _PanelActionTile(
            icon: Icons.tune,
            label: '编辑控制栏',
            subtitle: '管理右上角 5 个槽位按钮（添加 / 移除 / 排序）',
            onTap: () => PlayerPanelNavigator.of(panelContext).push(
              PlayerPanelPage(title: '编辑控制栏', body: _buildEditPanel()),
            ),
          ),
        ],
      ),
    );
  }

  /// 「编辑控制栏」页：已启用槽位（拖拽排序 + 文本「删除」）+ 可添加（文本「添加」）
  Widget _buildEditPanel() {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final enabled = _settings.topActions;
        final disabled = PlayerTopAction.values
            .where((a) => !enabled.contains(a))
            .toList();
        final full = enabled.length >= PlayerControlsSettings.maxTopActions;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (enabled.isNotEmpty) ...[
              const _PanelSectionLabel('已启用（长按拖拽排序）'),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: enabled.length,
                onReorderItem: (o, n) => _settings.reorderTopAction(o, n),
                itemBuilder: (context, index) {
                  final a = enabled[index];
                  return ListTile(
                    key: ValueKey(a.id),
                    leading: Icon(a.icon, color: Colors.white),
                    title: Text(
                      a.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: a.implemented
                        ? null
                        : const Text(
                            '功能即将上线',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                    trailing: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () => _settings.removeTopAction(a),
                      child: const Text('删除'),
                    ),
                  );
                },
              ),
              const Divider(height: 1, color: Colors.white12),
            ],
            if (disabled.isNotEmpty) ...[
              const _PanelSectionLabel('可添加'),
              for (final a in disabled)
                ListTile(
                  leading: Icon(a.icon, color: Colors.white),
                  title: Text(
                    a.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    !a.implemented
                        ? '功能即将上线'
                        : (full ? '槽位已满（5/5），需先移除一个' : ''),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: full ? null : () => _settings.addTopAction(a),
                    child: const Text('添加'),
                  ),
                ),
              const Divider(height: 1, color: Colors.white12),
            ],
            _PanelActionTile(
              icon: Icons.restart_alt,
              label: '重置控制栏',
              subtitle: '清空全部槽位（仅保留「更多」按钮）',
              onTap: _settings.resetTopActions,
            ),
          ],
        );
      },
    );
  }

  /// 点击顶栏槽位执行动作（比例 → 弹画面比例面板；其余占位提示即将上线）。
  /// 倍速已移至底栏固定按钮（见底栏），不在此列。
  void _handleSlotAction(PlayerTopAction action) {
    switch (action) {
      case PlayerTopAction.aspect:
        _openFitPanel();
      case PlayerTopAction.subtitle:
      case PlayerTopAction.danmaku:
      case PlayerTopAction.audio:
        if (!action.implemented) _showComingSoon(action.label);
    }
  }

  Future<void> _openSpeedPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_speedPanelPage()]);
    _resetHideTimer();
  }

  Future<void> _openSuperResolutionPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_superResolutionPanelPage()]);
    _resetHideTimer();
  }

  Future<void> _openFitPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_fitPanelPage()]);
    _resetHideTimer();
  }

  Future<void> _openMorePanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(
      context,
      pages: [PlayerPanelPage(title: '控制栏', body: _buildMorePanel())],
    );
    _resetHideTimer();
  }

  // ── 退出与进度 ──────────────────────────────────────────

  /// 退出播放器：保存进度、恢复设备状态（音量/亮度）、恢复竖屏，再返回
  Future<void> _exitPlayer() async {
    _saveProgress();
    await _restoreDeviceState();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    _controlsController.dispose();
    _unlockController.dispose();
    _speedNotifier.dispose();
    _preload.cancel();
    _saveProgress();
    // 兜底恢复设备状态（正常退出已走 _exitPlayer，这里防异常路径泄漏）
    _restoreDeviceState();
    DeviceServices.clearFrameCache();
    // 退出时强制恢复竖屏和系统 UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inMilliseconds);

  @override
  Widget build(BuildContext context) {
    // 拦截系统返回键（手势/三键），与左上角返回按钮走同一路径：
    // 先保存进度、恢复竖屏和系统 UI，再退出，避免横屏闪烁
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
                // 视频画面（禁用默认控件；画面比例由设置驱动；
                // 外层 Transform 承载双指缩放/平移）
                Positioned.fill(
                  child: Transform(
                    transform: _zoomMatrix(),
                    child: Video(
                      controller: _controller,
                      controls: NoVideoControls,
                      fit: _settings.videoFit.boxFit,
                      aspectRatio: _settings.videoFit.aspectRatio,
                    ),
                  ),
                ),
                // 手势层：单击/双击/长按（+左右滑动调速）/单指滑动
                // （音量·亮度·进度）/双指缩放平移
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
                    onSwipeCancel: _onSwipeCancel,
                    onZoomStart: _onZoomStart,
                    onZoomUpdate: _onZoomUpdate,
                    onZoomEnd: _onZoomEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
                // 控制层（锁定后全部隐藏）：
                // 顶栏顶部下落 / 底栏底部上升 / 右侧操作右侧滑入（Kazumi 风格）
                IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: SlideTransition(
                    position: _topSlide,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: PlayerTopBar(
                        title: _title,
                        onBack: _exitPlayer,
                        onMore: _openMorePanel,
                        onActionTap: _handleSlotAction,
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: SlideTransition(
                    position: _bottomSlide,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: PlayerBottomBar(
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
                          _requestThumbnail(v.round());
                          _resetHideTimer();
                        },
                        onSeekEnd: (v) {
                          _player.seek(Duration(milliseconds: v.round()));
                          setState(() {
                            _dragPosition = null;
                            _clearThumbnail();
                          });
                          _resetHideTimer();
                        },
                        hasNext: _hasNext,
                        onNext: _playNext,
                        timeText:
                            '${_fmt(_dragPosition ?? _position)} / ${_fmt(_duration)}',
                        onSpeedTap: _openSpeedPanel,
                        showSpeedButtonBackground:
                            _settings.showButtonBackground,
                        superResolutionLabel: '超分辨率',
                        onSuperResolutionTap: _openSuperResolutionPanel,
                      ),
                    ),
                  ),
                ),
                // 右侧操作（截图 / 锁定，从右侧滑入）
                IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: SlideTransition(
                    position: _rightSlide,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: PlayerRightActions(
                          locked: _locked,
                          onScreenshot: _takeScreenshot,
                          onToggleLock: _toggleLock,
                        ),
                      ),
                    ),
                  ),
                ),
                // 中央控制簇（淡入）
                IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: FadeTransition(
                    opacity: _controlsController,
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
                // 锁定状态：左右两侧滑入解锁按钮（单击屏幕可呼出/隐藏）
                if (_locked)
                  SlideTransition(
                    position: _leftUnlockSlide,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _UnlockButton(onTap: _unlock),
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
                        child: _UnlockButton(onTap: _unlock),
                      ),
                    ),
                  ),
                // 双击快进/快退反馈徽章（贴近横屏顶部区域，但不完全贴边）
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
                // 音量/亮度手势指示器：音量在左侧、亮度在右侧（对称），
                // kazumi 风格：从屏幕边缘滑入（音量从左、亮度从右）+ 淡入。
                // 位置由 _indicatorKind 决定（退场动画期间 _indicator 为
                // null，但仍沿用最近类型，避免退场跳边）
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
                        visible: _longPressing &&
                            _settings.showSpeedIndicator,
                        dynamicActive: _dynamicSpeedActive,
                        showBar: _speedBarVisible,
                        showHint: !_settings.speedHintShown,
                        presets: dynamicSpeedPresets(),
                      ),
                    ),
                  ),
                ),
                // 进度条拖动缩略图预览（进度条上方跟随拖动位置）
                if (_thumbPreview != null && _dragPosition != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 104,
                    child: PlayerThumbnailPreview(
                      bytes: _thumbPreview!.bytes,
                      time: _thumbPreview!.time,
                      fraction: _thumbFraction,
                      visible: true,
                    ),
                  ),
                // 双指缩放后显示「还原画面」入口（播放/暂停按钮下方，
                // 与中央簇保持一定间距；比原位置再往下移一些）
                if (_zoomScale != 1.0 || _zoomOffset != Offset.zero)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, 0.34),
                      child: _ZoomRestoreChip(onTap: _resetZoom),
                    ),
                  ),
                // 常驻进度线（设置开启且控制层隐藏时显示；锁定后不显示）
                if (_settings.showProgressLine &&
                    !_controlsVisible &&
                    !_locked &&
                    _duration > Duration.zero)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2.5,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 2.5,
                          color: Colors.white.withValues(alpha: 0.25),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (_position.inMilliseconds /
                                    _duration.inMilliseconds)
                                .clamp(0.0, 1.0),
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.8),
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

/// 锁定状态下的解锁按钮（屏幕左右两侧各一个）。
/// 固定灰黑圆角背景（与右侧截图/锁定按钮同款），点击解锁。
class _UnlockButton extends StatelessWidget {
  final VoidCallback onTap;

  const _UnlockButton({required this.onTap});

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

/// 「更多」面板中的动作行：图标 + 名称 +（副标题）+ 箭头
class _PanelActionTile extends StatelessWidget {  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _PanelActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}

/// 「编辑控制栏」页内的小节标题（已启用 / 可添加）
class _PanelSectionLabel extends StatelessWidget {
  final String text;

  const _PanelSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 双指缩放后的「还原画面」胶囊（PiliPlus 同款，点击恢复 1:1）
class _ZoomRestoreChip extends StatelessWidget {
  final VoidCallback onTap;

  const _ZoomRestoreChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text(
              '还原画面',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
