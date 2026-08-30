import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/pages/player/audio_player_page.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/pages/player/player_portrait_page.dart';
import 'package:moumou/pages/player/views/audio_panel.dart';
import 'package:moumou/pages/player/views/equalizer_panel.dart';
import 'package:moumou/pages/player/views/player_bottom_bar.dart';
import 'package:moumou/pages/player/views/player_chapter_bar.dart';
import 'package:moumou/pages/player/views/player_chapter_panel.dart';
import 'package:moumou/pages/player/views/player_center_cluster.dart';
import 'package:moumou/pages/player/views/player_danmaku_layer.dart';
import 'package:moumou/pages/player/views/player_danmaku_network_panel.dart';
import 'package:moumou/pages/player/views/player_danmaku_panel.dart';
import 'package:moumou/pages/player/views/player_danmaku_settings_panel.dart';
import 'package:moumou/pages/player/views/player_decode_panel.dart';
import 'package:moumou/pages/player/views/player_fit_panel.dart';
import 'package:moumou/pages/player/views/player_gesture_indicator.dart';
import 'package:moumou/pages/player/views/player_gesture_layer.dart';
import 'package:moumou/pages/player/views/player_intro_outro_panel.dart';
import 'package:moumou/pages/player/views/player_loop_panel.dart';
import 'package:moumou/pages/player/views/player_playlist_panel.dart';
import 'package:moumou/pages/player/views/player_resume_indicator.dart';
import 'package:moumou/pages/player/views/player_right_actions.dart';
import 'package:moumou/pages/player/views/player_speed_indicator.dart';
import 'package:moumou/pages/player/views/player_speed_panel.dart';
import 'package:moumou/pages/player/views/player_status_bar.dart';
import 'package:moumou/pages/player/views/player_super_resolution_panel.dart';
import 'package:moumou/pages/player/views/player_swipe_seek_overlay.dart';
import 'package:moumou/pages/player/views/player_thumbnail_preview.dart';
import 'package:moumou/pages/player/views/player_top_bar.dart';
import 'package:moumou/pages/player/views/subtitle_panel.dart';
import 'package:moumou/services/audio_service.dart';
import 'package:moumou/services/chapter_tracker.dart';
import 'package:moumou/services/danmaku_service.dart';
import 'package:moumou/services/danmaku_network_service.dart';
import 'package:moumou/services/decode_settings.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/fast_thumbnails.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/services/intro_outro_tracker.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/subtitle_service.dart';
import 'package:moumou/services/subtitle_settings.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/utils/intro_outro_skip.dart';
import 'package:moumou/utils/pip_aspect.dart';
import 'package:moumou/utils/playback_completion.dart';
import 'package:moumou/utils/playback_restore.dart';
import 'package:moumou/utils/player_gestures.dart';
import 'package:moumou/widgets/app_frame.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  late String _path;
  late String _title;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _playing = false;

  // ── 播放位置/时长（risk_audit #1）────────────────────────
  // 位置流几十毫秒来一次事件。整页 setState 会重建整棵 Stack（视频层/手势层/
  // 顶栏/底栏/右侧按钮/中央簇…），而实际只有进度条、时间文本、常驻进度线
  // 需要跟随。改为页面级 ValueNotifier：进度条/时间/进度线用
  // [_progressListenable] 局部订阅只重建自身；页面级 setState 只留给低频状态
  // （播放/暂停、控制层显隐、锁定、切集等）。
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> _dragPositionNotifier = ValueNotifier(null);

  Duration get _position => _positionNotifier.value;
  Duration get _duration => _durationNotifier.value;
  Duration? get _dragPosition => _dragPositionNotifier.value;

  /// 进度相关监听合并：底栏（进度条/时间文本）与常驻进度线局部订阅用
  late final Listenable _progressListenable = Listenable.merge([
    _positionNotifier,
    _durationNotifier,
    _dragPositionNotifier,
  ]);

  /// 章节监听合并：底栏（进度条标记/章节名称）+ 胶囊浮层订阅用
  late final Listenable _chapterListenable =
      Listenable.merge([_progressListenable, _chapterTracker]);

  /// 底栏监听合并：章节 + 弹幕开关状态（弹幕开关图标随 danmakuOn 刷新）
  late final Listenable _bottomBarListenable =
      Listenable.merge([_chapterListenable, _danmakuController]);

  /// 章节状态跟踪器（工作.md 章节功能）：读取章节与跳过片段、跟踪当前
  /// 章节与胶囊自动弹出窗口；横竖屏共享同一实例（切集/位置流统一驱动）。
  late final ChapterTracker _chapterTracker;

  /// 字幕控制器（工作.md 阶段1 第 3 点）：轨道列表/主次字幕/外挂导入/设置应用；
  /// 横竖屏共享同一实例（同一 Player，切集后统一重新应用）。
  late final SubtitleController _subtitleController;

  /// 音频控制器（工作.md 音频功能）：音轨列表/切音轨/外部音轨导入·移除/
  /// 声道/音频处理；横竖屏共享同一实例（同一 Player，切集后统一重新应用）。
  late final AudioController _audioController;

  /// 弹幕控制器（弹幕移植方案阶段1）：本地同名弹幕加载 + 秒桶调度发射 +
  /// canvas 渲染层驱动；横竖屏共享同一实例（同一 Player，切集后重新加载）。
  late final DanmakuController _danmakuController;

  /// 片头片尾状态跟踪器（工作.md 片头片尾功能）：驱动片头/片尾自动跳过
  /// 动作；横竖屏共享同一实例（切集/位置流统一驱动）。
  late final IntroOutroTracker _introOutroTracker =
      IntroOutroTracker(IntroOutroSettings.instance);

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

  /// 当前预览（frame 为 null 表示帧仍在加载，先显示占位 + 时间）
  ({FastThumbFrame? frame, Duration time})? _thumbPreview;
  double _thumbFraction = 0;

  /// 气泡可见性（拖动中 true；松手淡出后 false 再卸载）
  bool _thumbVisible = false;
  Timer? _thumbHideTimer;
  int _lastThumbBucketMs = -1;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// 是否存在「下一集」（playlist 中当前视频之后还有视频）
  bool get _hasNext {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return false;
    final idx = list.indexWhere((v) => v.path == _path);
    return idx >= 0 && idx < list.length - 1;
  }

  // ── 恢复进度 / 播放完成（EOF）处理 ──────────────────────

  /// 把 mpv 的 hr-seek 设为 absolute：绝对 seek 一律精确（从上一关键帧
  /// 解码到目标帧）。长 GOP 视频松手后可能多等几十毫秒，换取所见即所得。
  Future<void> _applyExactSeek() async {
    try {
      final native = _player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      await native.setProperty('hr-seek', 'absolute');
    } catch (_) {
      // 播放器初始化失败时随打开流程报错，此处静默
    }
  }

  /// 应用解码预设（mpv 内置 profile）：需在 open 前写入，
  /// 重启播放器（重开视频）后生效；默认「快速」。
  Future<void> _applyDecodePreset() async {
    try {
      final native = _player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      final profile = DecodeSettings.instance.preset.profile;
      if (profile.isNotEmpty) {
        await native.setProperty('profile', profile);
      }
    } catch (_) {
      // 播放器初始化失败时随打开流程报错，此处静默
    }
  }

  /// 应用 GPU 渲染后端：开启 gpu-next + Vulkan 时写入 `gpu-api=vulkan`
  /// （libplacebo 选 Vulkan；否则 gpu-next 默认走 OpenGL）。需在 open 前写入，
  /// 重启播放器（重开视频）后生效。
  Future<void> _applyGpuApi() async {
    try {
      final native = _player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      final d = DecodeSettings.instance;
      if (d.gpuNext && d.useVulkan) {
        await native.setProperty('gpu-api', 'vulkan');
      }
    } catch (_) {
      // 播放器初始化失败时随打开流程报错，此处静默
    }
  }

  /// 恢复进度指示器是否可见（恢复到位后显示，自管理 2.5s 隐藏）
  bool _resumeVisible = false;

  /// 正在恢复进度（true 时用不透明封层盖住视频：暂停加载 + seek 都在
  /// 封层下进行，用户看不到 mpv 暂停态渲染的 0 时刻第一帧海报；位置
  /// 确认到位后揭开 + 播放，首帧即目标帧——v5 重写，无开头闪现）。
  bool _restoring = false;

  /// 正在切换视频（防 EOF 重入：切集期间旧文件可能触发 completed 事件）
  bool _isSwitchingVideo = false;

  /// 正在处理播放完成事件（防 completed 流重复触发）
  bool _isHandlingEndOfFile = false;

  /// 竖屏页打开期间为 true：本页（横屏）的 EOF 处理让位给竖屏页
  /// （两者共享同一 [Player]，若都处理 completed 会重复切集）
  bool _portraitActive = false;

  /// 听视频页打开期间为 true：本页的 EOF 处理让位给听视频页
  /// （听视频页共享同一 [Player] 并自行处理切歌/随机/循环）。
  /// 用 ValueNotifier 供 Video 的 pauseUponEnteringBackgroundMode 局部订阅：
  /// 听视频页打开时退后台不暂停（后台播放），否则保持默认退后台暂停。
  final ValueNotifier<bool> _audioActive = ValueNotifier(false);

  /// 已开始退出播放页（异步退出流程中禁止再自动 push 竖屏页，防栈错乱）
  bool _exiting = false;

  /// 退出期间横屏页整体黑化（竖屏退出时置位，盖住下层横屏页的 UI 骨架，
  /// 保证任何时刻两层页面不同框，从机制上杜绝「两个竖屏界面」复现）。
  bool _exitBlackout = false;

  /// 播放器是否已销毁（退出路径先 await 销毁，widget dispose 兜底防重复）
  bool _playerDisposed = false;

  /// 页面已销毁（risk_audit #2）：dispose 置位，异步恢复/打开流程的每个
  /// await 之后先查它，播放器销毁后的后续操作直接放弃——
  /// 防止快速「退出→进入」循环里恢复流程继续 seek 抛
  /// `AssertionError: [Player] has been disposed` 被全局兜底写成假崩溃日志。
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _path = widget.path;
    _title = widget.title;
    // 开启 libass：走 mpv 原生字幕渲染（sub-visibility=yes），而非 Flutter
    // SubtitleView。这也是内嵌字幕原生样式 / 各种 sub-* 样式属性生效的前提。
    // 自定义字体必须在 mpv_initialize 前通过 libassAndroidFontsDir/Name 注入
    // （运行时 setProperty 改 sub-fonts-dir 会破坏 libass 字体缓存导致字幕消失）。
    final subFont = SubtitleSettings.instance.font;
    final subFontsDir = SubtitleSettings.instance.fontsDir;
    final useCustomFont = subFont != 'auto' && subFontsDir.isNotEmpty;
    _player = Player(
      configuration: PlayerConfiguration(
        libass: true,
        libassAndroidFontsDir: useCustomFont ? subFontsDir : null,
        libassAndroidFontName: useCustomFont ? subFont : null,
      ),
    );
    // 解码档位注入（方案 A）：创建时传入 hwdec/vo，换档后下次打开视频生效
    final decodeSettings = DecodeSettings.instance;
    final decodeMode = decodeSettings.mode;
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        vo: decodeSettings.gpuNext ? 'gpu-next' : 'gpu',
        enableHardwareAcceleration: decodeMode != DecodeMode.sw,
        hwdec: decodeMode.hwdec,
      ),
    );
    // 章节跟踪器：绑定同一播放器（mpv chapter-list 子属性读取）
    _chapterTracker = ChapterTracker(MpvChapterSource(_player));
    // 字幕控制器：绑定同一播放器（track-list / sid / sub-add 单选模型）；
    // 初始化就绪后应用一次设置（延迟/样式等在首帧前生效）
    _subtitleController = SubtitleController(_player);
    // 同名字幕自动加载成功后弹提示（服务层不依赖 UI，由页面层展示）
    _subtitleController.onAutoLoadedSubtitle = (fileName) {
      if (mounted) _toast('已自动加载字幕：$fileName');
    };
    unawaited(_subtitleController.applyOnInit());
    // 音频控制器：绑定同一播放器（track-list / aid / audio-add / 声道 / af）
    _audioController = AudioController(_player);
    unawaited(_audioController.applyOnInit());
    // 弹幕控制器：绑定同一播放器（本地同名弹幕加载 + 1s 秒桶发射 +
    // 渲染层暂停/倍速同步；首开加载在 _openAndSetRate 的 open 完成后）
    _danmakuController = DanmakuController(_player);
    // 自动加载弹幕（同名/记忆恢复）成功后弹提示（服务层不依赖 UI）
    _danmakuController.onAutoLoadedDanmaku = (fileName) {
      if (mounted) _toast('已自动加载弹幕：$fileName');
    };
    // 网络弹幕（弹弹Play 搜索选中/自动匹配/切集自动匹配）加载成功提示
    _danmakuController.onNetworkDanmakuLoaded = (message) {
      if (mounted) _toast('已加载弹幕：$message');
    };
    // 精确落帧：hr-seek=absolute 后所有绝对 seek 帧级精确解码
    // （对齐 mpvRx 的 "seek absolute+exact"——拖动松手即停在预览帧，
    // 而非落在最近关键帧）
    unawaited(_applyExactSeek());
    // 解码预设（vd-lavc-*）：open 前写入，重启播放器后生效
    unawaited(_applyDecodePreset());
    // GPU 后端（gpu-api=vulkan）：open 前写入，重启播放器后生效
    unawaited(_applyGpuApi());

    // 工作.md 第 7 点：关闭「启用播放界面动画」后，控制层/解锁按钮
    // 的进出场动画时长归零（forward/reverse 立即完成，直接出现/消失）
    if (!_settings.playerAnimations) {
      _controlsController.duration = Duration.zero;
      _unlockController.duration = Duration.zero;
    }

    // 倍速记忆：启用时恢复上次倍速
    _speed = _settings.rememberSpeed ? _settings.lastSpeed : 1.0;
    _speedNotifier.value = _speed;
    // 进入播放器：未开启记忆时本次会话从「关闭/均衡」开始超分
    // （退出播放/重启后自动回到默认关闭，记忆开启才恢复上次设置）
    SuperResolutionService.instance.enterPlayer();
    // 同步系统音量/亮度作为本次会话起点（音量从手机当前音量开始）
    _initDeviceState();
    _openAndSetRate();

    // 初始方向（工作.md 第 5 点：视频方向设置）：
    // 锁定竖屏 → 直接竖屏；其余（自动/锁定横屏）先横屏，
    // 「自动」会在 open 完成后按视频方向决定是否切竖屏
    final lockPortrait =
        _settings.videoOrientation == VideoOrientationMode.portrait;
    SystemChrome.setPreferredOrientations(lockPortrait
        ? [DeviceOrientation.portraitUp]
        : [
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
          // 暂停时总是显示控制层（含中央播放键）；
          // 退出期间 pause 冻结末帧不弹控制层（防退出时控制条闪现）
          if (!p && !_locked && !_exiting) {
            _controlsVisible = true;
            _controlsController.forward();
          }
        });
      }),
    );
    // 位置/时长：只更新 ValueNotifier，不再整页 setState（risk_audit #1）
    _subs.add(
      _player.stream.position.listen((p) {
        if (!_disposed && mounted) _positionNotifier.value = p;
        // 章节跟踪：当前章节/跳过片段/胶囊自动弹出窗口随位置推进
        _chapterTracker.onPositionChanged(p);
        // 片头片尾：竖屏页/听视频页打开期间让位（共享同一 Player，
        // 避免重复 seek / 切集）
        if (_portraitActive || _audioActive.value) return;
        _handleIntroOutroPosition(p);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (!_disposed && mounted) _durationNotifier.value = d;
        // 恢复进度改由 _openAndSetRate（open 完成后）统一触发，
        // 避免 mpv 加载期 seek 被丢弃（历史 bug：指示器出现但进度不回位）。
        // 缩略图预热不再进入播放即触发：改为「用户第一次拖动进度条时」
        // 才从当前位置向外预热（见 _requestThumbnail），省去不拖动用户的
        // 后台解码与缓存占用。
      }),
    );
    // 播放完成（EOF）：走 handleEndOfFile 同款优先级链
    // （单集循环→自动连播→列表循环→自动退出→自动暂停），带防重入标志
    _subs.add(
      _player.stream.completed.listen((completed) {
        if (completed) _onPlaybackCompleted();
      }),
    );

    _resetHideTimer();
  }

  /// 读取保存进度并做阈值过滤（Kazumi `resumedNearEnd` 同思路）：
  /// - 无进度 / ≤0 → null（从头播）；
  /// - 已知时长且 `saved / duration < 5%` 或 `≥ 已观看阈值`（默认 95%，
  ///   已看完）→ null（从头播，避免 seek 定位到结尾立即触发 EOF 连播）。
  ///   时长优先用播放列表 MediaStore 的 durationMs（open 前就可知，
  ///   不必等 mpv 上报）；列表无时长信息时按「有进度就恢复」处理，
  ///   交给 [openAndRestore] 在时长就绪后 seek + 确认。
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

  /// 打开媒体、设置倍速、应用超分着色器，并按需恢复进度。
  ///
  /// **恢复进度 v5 重写（用户反馈 v5：仍有 1–1.5s 开头闪现）**：
  /// 弃用 `Media(start:)`（media_kit 1.2.x 的 on_load hook 读 playlist-pos
  /// 时恒为 -1，start 从未生效），改用 [openAndRestore] 的**确定性恢复**：
  /// 暂停加载 → 静音激活时间线 → seek → 位置确认，全程用不透明封层盖住
  /// 视频，到位后再揭开 + 播放，首帧即目标帧，无开头闪现、无可见跳转。
  ///
  /// 之后按「视频方向」设置决定是否自动进入竖屏播放。
  ///
  /// 防销毁竞态（risk_audit #2）：initState 发起本流程但未 await，用户可能
  /// 在其完成前退出——每个 await 之后先查 [_disposed]/mounted，播放器已
  /// 销毁时静默返回，避免 AssertionError 写假崩溃日志。
  Future<void> _openAndSetRate() async {
    // 读取保存进度（ensureLoaded 防重启后读空缓存，见 §7 竞态修复）
    await PlaybackProgressService.instance.ensureLoaded();
    if (_disposed || !mounted) return;
    final start = _resumeStartFor(_path);
    // 片头片尾：新媒体重置跟踪状态（open 期间位置事件不评估）
    _introOutroTracker.reset();
    // 恢复时先盖住视频：暂停加载 + seek 期间用户看不到 0 时刻海报
    if (start != null && mounted) setState(() => _restoring = true);
    var restored = false;
    try {
      restored = await openAndRestore(
        _player,
        _path,
        saved: start,
        // 倍速 + 超分在播放/seek 之前完成（避免 shader 变化重置位置）
        prepare: () async {
          await _player.setRate(_speed);
          try {
            await SuperResolutionService.instance.apply(_player);
          } catch (_) {
            // 忽略：超分失败不影响播放与进度恢复
          }
        },
      );
      if (_disposed || !mounted) return;
      // 揭开封层（openAndRestore 已 seek 到位并开始播放）
      if (mounted) setState(() => _restoring = false);
      if (restored && start != null) {
        _positionNotifier.value = start;
        _showResumeIndicator();
      }
    } on AssertionError {
      // 播放器已在打开过程中被销毁（快速退出→进入循环）：静默返回
      return;
    }
    if (_disposed || !mounted) return;
    // 片头片尾：恢复点感知后标记就绪，位置事件开始评估
    // （恢复点 > 0 时不跳片头；恢复点落在片尾时不立即切集）
    if (restored && start != null) {
      _introOutroTracker.markResumedPosition(start, _player.state.duration);
    }
    _introOutroTracker.markReady();
    // 章节功能：open 完成后读取章节（此时时长已就绪；空章节静默清空）
    unawaited(_chapterTracker.load());
    // 字幕功能：open 完成后刷新轨道/重新添加外挂字幕/应用设置
    unawaited(_subtitleController.reapplyForMedia(_path));
    // 音频功能：open 完成后刷新音轨/同步当前音轨/应用声道与音频处理
    unawaited(_audioController.reapplyForMedia(_path));
    // 弹幕功能：open 完成后加载同目录同名弹幕（无匹配静默跳过）
    unawaited(_danmakuController.loadForVideo(_path));
    await _applyVideoOrientation();
  }

  /// 视频方向（工作.md 第 5 点）：
  /// - 锁定横屏：保持横屏（不动作）；
  /// - 锁定竖屏：自动进入竖屏播放页（共享同一 Player，音频零中断）；
  /// - 自动：按视频方向（宽高比）决定横/竖屏。
  ///
  /// 防销毁竞态（risk_audit #2）：`_isPortraitVideo` 可能等待播放器
  /// videoParams 流，期间用户退出则播放器已销毁——抛 AssertionError 时
  /// 静默返回，不写假崩溃日志。
  Future<void> _applyVideoOrientation() async {
    if (_settings.videoOrientation == VideoOrientationMode.landscape) return;
    try {
      final portrait =
          _settings.videoOrientation == VideoOrientationMode.portrait ||
              await _isPortraitVideo();
      if (!portrait) return;
      // 已在竖屏页（用户手动切过）或已开始退出时不再自动 push
      if (!mounted || _portraitActive || _exiting || _disposed) return;
      // 先切方向再进竖屏页，避免先横屏闪一下再旋转
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await _openPortraitPlayer();
    } on AssertionError {
      // 播放器已被销毁（快速退出）：静默返回
    }
  }

  /// 判断当前视频是否为竖屏，**结合旋转元数据**（工作.md 第 5 点，参考小喵 KT：
  /// `video-params/aspect` + `video-params/rotate`）。手机竖拍视频常见
  /// 「编码尺寸为横屏 + rotation 90/270」，直接按编码宽高判断会误判为横屏。
  ///
  /// 实现要点（与 KT 一致的算法）：
  /// - 用 [VideoParams] 的**原始 w/h**（未经 aspect/旋转修正）与 rotate；
  ///   ⚠️ 不要用 `state.width/height`——media_kit 已把它们按 rotate 交换成
  ///   显示尺寸，若再套用 rotate 会**双重交换**导致误判（上一轮 bug 根因）；
  /// - rotate 为 90/270 时显示方向互换（aspect = 1/aspect），宽高比 ≤ 1 即竖屏。
  ///
  /// 优先等播放器上报（最多 2 秒）；仍未知再用播放列表里的分辨率
  /// （MediaStore，无旋转信息，仅作近似）。
  Future<bool> _isPortraitVideo() async {
    final (w, h, rotate) = await _waitVideoSize();
    if (w > 0 && h > 0) {
      final swapped = rotate % 180 == 90;
      // 显示宽高比 = 原始 w/h；rotate 90/270 时互换
      final displayRatio = swapped ? h / w : w / h;
      return displayRatio <= 1.0;
    }
    final list = widget.playlist;
    if (list != null) {
      for (final v in list) {
        if (v.path == _path && v.width > 0 && v.height > 0) {
          return v.height > v.width;
        }
      }
    }
    return false;
  }

  /// 等待播放器上报**原始**画面尺寸与旋转角（videoParams 流的 w/h/rotate，
  /// 未经 aspect/旋转修正），最多 [timeout]。返回 `(宽, 高, 旋转角)`；
  /// 超时返回 `(0, 0, 0)`。
  /// 播放器已销毁时（快速退出）抛 AssertionError，由调用方捕获静默处理。
  Future<(int, int, int)> _waitVideoSize({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final params = _player.state.videoParams;
    final w0 = params.w;
    final h0 = params.h;
    final rotate0 = params.rotate ?? 0;
    if (w0 != null && w0 > 0 && h0 != null && h0 > 0) {
      return (w0, h0, rotate0);
    }
    final completer = Completer<(int, int, int)>();
    late final StreamSubscription<VideoParams> sub;
    sub = _player.stream.videoParams.listen((p) {
      // 用原始 w / h（非 aspect 修正、非 rotate 交换），rotate 单独取
      if (p.w != null && p.w! > 0 && p.h != null && p.h! > 0 &&
          !completer.isCompleted) {
        completer.complete((p.w!, p.h!, p.rotate ?? 0));
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete((0, 0, 0));
    });
    final size = await completer.future;
    timer.cancel();
    await sub.cancel();
    return size;
  }

  /// 读取系统音量/亮度作为本次会话起点：
  /// - 音量：以手机当前系统音量为播放音量起点（如 20%）；
  /// - 亮度：读系统亮度并应用到窗口（kt/mpvEx 做法），保证指示器数值
  ///   与屏幕实际亮度一致；退出时恢复 -1 交还系统控制（自动亮度恢复）。
  ///
  /// 音量语义（v3 用户反馈修复）：手势直接控制系统媒体音量（真实响度），
  /// 播放器 mpv 音量固定 100（0dB 增益）——否则「系统 20% 进入 → 手势调到
  /// 100%」实际输出仍只有 20%（mpv 增益受系统音量上限约束）。
  Future<void> _initDeviceState() async {
    final vol = await DeviceServices.getSystemVolume();
    _initialSystemVolume = vol;
    _volume = vol ?? 50;
    // mpv 音量固定满增益；手势改调系统音量（见 _onVerticalSwipe）
    try {
      await _player.setVolume(100);
    } on AssertionError {
      // 播放器已被销毁（快速退出）：后续操作放弃
      return;
    }
    if (_disposed || !mounted) return;
    final brightness = await DeviceServices.getBrightness();
    if (brightness != null) {
      _brightness = brightness;
      // 锁到窗口，使屏幕显示与指示器一致（播放期间亮度不随自动亮度漂移）
      await DeviceServices.setWindowBrightness(brightness);
    }
    if (!_disposed && mounted) setState(() {});
  }

  /// 退出播放时恢复设备状态：
  /// - 亮度：恢复 -1（交还系统控制 = 进入播放前的状态）；
  /// - 音量：手势已直控系统音量（v3 语义）——开启「保存到系统」保持当前值
  ///   （本页 [_volume] 可能因竖屏页手势而陈旧，**不得**用它覆写系统音量）；
  ///   关闭 → 恢复进入前的系统音量。
  Future<void> _restoreDeviceState() async {
    await DeviceServices.setWindowBrightness(null);
    if (!_settings.saveVolumeToSystem) {
      await DeviceServices.setSystemVolume(_initialSystemVolume ?? _volume);
    }
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

  // ── 应用生命周期（画中画 / 听视频相关）──────────────────

  /// 应用生命周期变化：
  /// - 退后台 / 进入画中画（Android PiP 会触发 paused/hidden）：
  ///   隐藏控制层（PiP 期间不显示控制，播放保持）；
  /// - 返回前台（PiP 关闭返回 / 从后台切回）：恢复控制层并重置隐藏计时。
  ///
  /// 原生侧没有 PiP 事件回传通道（t3 只提供 isPipSupported/enterPip/
  /// setAutoPipEnabled 三个方法），故用 AppLifecycleState 判断进出 PiP。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _hideTimer?.cancel();
        if (mounted && _controlsVisible && !_locked) {
          setState(() => _controlsVisible = false);
          _controlsController.reverse();
        }
      case AppLifecycleState.resumed:
        if (mounted && !_locked && !_controlsVisible) {
          setState(() => _controlsVisible = true);
          _controlsController.forward();
        }
        _resetHideTimer();
      default:
        break;
    }
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
      // 右侧：音量（直控系统媒体音量 = 真实响度；退出时按设置写回/恢复，
      // 见 _restoreDeviceState；v3 用户反馈：只调 mpv 增益受系统音量上限约束）
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
      maxGapMs: 3000,
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

  // ── 弹幕（阶段2：显示/隐藏 + 本地加载 + 设置面板）──────────────

  /// 弹幕开关（底栏按钮 / 顶栏「弹幕」槽位共用）：关闭时清屏并作废在途
  /// 发射，开启后从当前位置继续
  void _toggleDanmaku() {
    _danmakuController.toggle();
    _resetHideTimer();
  }

  /// 弹幕设置：打开弹幕设置面板（右侧滑入，[showPlayerPanel]）。
  /// 横屏左下角时间右侧的弹幕设置按钮 / 更多→弹幕→弹幕设置进入同一面板。
  Future<void> _openDanmakuSettingsPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(
      context,
      pages: [
        const PlayerPanelPage(
          title: '弹幕设置',
          body: PlayerDanmakuSettingsPanel(),
        ),
      ],
    );
    _resetHideTimer();
  }

  // ── 片头片尾 ─────────────────────────────────────────────

  /// 片头片尾面板页（顶栏「片头片尾」槽位弹出）
  PlayerPanelPage _introOutroPanelPage() => PlayerPanelPage(
        title: '片头片尾',
        body: PlayerIntroOutroPanel(
          positionListenable: _positionNotifier,
          durationListenable: _durationNotifier,
        ),
      );

  /// 打开片头片尾设置面板（右侧滑入，[showPlayerPanel]）。
  Future<void> _openIntroOutroPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_introOutroPanelPage()]);
    _resetHideTimer();
  }

  /// 片头片尾自动跳过：位置流每次更新调用（横屏页在竖屏/听视频
  /// 打开期间让位，见位置流订阅处的门控）。
  ///
  /// - 跳过片头：seek 到片头结束并提示；
  /// - 跳过片尾：提示并自动播放下一集（[resolveIntroOutroAction] 已
  ///   保证存在下一集才产生此动作）。
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

  // ── 下一集 / 切集 ───────────────────────────────────────

  /// 手动/自动「下一集」：定位播放列表中的下一项后统一切集。
  Future<void> _playNext() async {
    final list = widget.playlist;
    if (list == null) return;
    final idx = list.indexWhere((v) => v.path == _path);
    if (idx < 0 || idx >= list.length - 1) return;
    final next = list[idx + 1];
    await _switchTo(next.path, next.name);
  }

  /// 列表循环：回到播放列表第一集。
  Future<void> _playFirst() async {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return;
    final first = list.first;
    await _switchTo(first.path, first.name);
  }

  /// 统一切集路径（自动连播 / 手动下一集 / 列表循环 / 后续列表选择都用它）：
  ///
  /// 1. 置 [_isSwitchingVideo] 防 EOF 重入（切集时旧文件可能触发 completed）；
  /// 2. **切集前必须 [_saveProgress]**（进度记忆要求：任何切换路径都先记旧进度，
  ///    必须在 `_path` 更新前调用）；
  /// 3. 打开新媒体（恢复时暂停加载 + 封层 + seek，见 [openAndRestore]）并
  ///    重设倍速、超分着色器（mpv 打开新文件时 glsl-shaders 需重确认）；
  /// 4. 重置播放页状态与恢复指示器（新视频各自恢复自己的进度）。
  Future<void> _switchTo(String path, String title) async {
    _isSwitchingVideo = true;
    try {
      // 章节功能：先清空旧媒体的章节标记（防 open 期间旧数据闪现）
      _chapterTracker.clear();
      // 字幕功能：清空旧媒体轨道（切集后重新加载）
      _subtitleController.clear();
      // 音频功能：清空旧媒体音轨（切集后重新加载；外部音轨临时不跨集保留）
      _audioController.clear();
      // 片头片尾：重置跟踪状态（open 期间位置事件不评估）
      _introOutroTracker.reset();
      if (mounted) {
        setState(() => _resumeVisible = false);
      }
      await _saveProgress(forcePersist: true);
      // 新视频的保存进度：open 时恢复（阈值过滤见 [_resumeStartFor]，
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
      if (_disposed || !mounted) return;
      if (mounted) {
        setState(() {
          _path = path;
          _title = title;
          // 同步播放器真实状态（此时文件已加载，时长/位置已就绪；
          // 不能置零——duration 流事件在 open 阶段已发出，不会再重发）
          _positionNotifier.value = _player.state.position;
          _durationNotifier.value = _player.state.duration;
          _dragPositionNotifier.value = null;
          _zoomScale = 1.0;
          _zoomOffset = Offset.zero;
          _indicator = null;
          _swipeSeekData = null;
          _restoring = false;
          _clearThumbnail();
        });
      }
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
      // 字幕功能：切集后重新添加外挂字幕 + 刷新轨道 + 应用设置
      unawaited(_subtitleController.reapplyForMedia(path));
      // 音频功能：切集后刷新音轨 + 同步当前音轨 + 应用声道与音频处理
      unawaited(_audioController.reapplyForMedia(path));
      // 弹幕功能：切集后重新加载新集的同名弹幕（loadForVideo 内部会先
      // 重置调度器并清屏，在途旧集弹幕不会灌入新集）
      unawaited(_danmakuController.loadForVideo(path));
    } on AssertionError {
      // 播放器已被销毁（切集过程中退出）：静默返回，不写假崩溃日志
      return;
    } finally {
      _isSwitchingVideo = false;
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

  /// 「更多」面板主页：未放入槽位的动作 +「编辑控制栏」入口。
  ///
  /// 工作.md 第 14 点：未放置到顶部 5 槽位的动作自动出现在「更多」里
  /// （「编辑控制栏」入口上方），同时也在「编辑控制栏 → 可添加」里。
  /// 用 ListenableBuilder 监听设置：在编辑控制栏内增删槽位后返回本页自动刷新。
  Widget _buildMorePanel() {
    // 用 Builder 取面板树内的 context：PlayerPanelNavigator.of 要求调用方
    // 位于 _PanelNavigatorScope 之下（在弹窗路由内），不能直接用 State 的 context
    // （历史 bug：of() 断言 scope == null，编辑控制栏点击无反应）。
    return Builder(
      builder: (panelContext) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final notPlaced = PlayerTopAction.values
              .where((a) => !_settings.topActions.contains(a))
              .toList();
          return ListView(
            key: const PageStorageKey('more_panel'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (notPlaced.isNotEmpty) ...[
                const _PanelSectionLabel('未放置的功能'),
                // 面板类动作面板内 push（返回按钮可回「更多」）；
                // 动作类（画中画/听视频）由 [_handlePanelAction] 关闭面板后执行
                for (final a in notPlaced)
                  _PanelActionTile(
                    icon: a.icon,
                    label: a.label,
                    subtitle: a.implemented ? null : '功能即将上线',
                    onTap: () => _handlePanelAction(panelContext, a),
                  ),
                const Divider(height: 1, color: Colors.white12),
              ],
              _PanelActionTile(
                icon: Icons.tune,
                label: '编辑控制栏',
                onTap: () => PlayerPanelNavigator.of(panelContext).push(
                  PlayerPanelPage(title: '编辑控制栏', body: _buildEditPanel()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 「编辑控制栏」页：已启用槽位（拖拽排序 + 文本「删除」）+ 可添加（文本「添加」）
  ///
  /// 已启用/可添加两区覆盖全部 [PlayerTopAction.values]（9 个动作：字幕/弹幕/
  /// 音频/比例/画中画/听视频/均衡器/解码/片头片尾），增删/排序沿用
  /// [_settings]（addTopAction/removeTopAction/reorderTopAction）。
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
            const _PanelSectionLabel('已启用（长按拖拽排序）'),
            if (enabled.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: enabled.length,
                onReorderItem: (o, n) => _settings.reorderTopAction(o, n),
                // 拖拽高亮修复（工作.md 第 14 点）：默认 proxy 是 M3
                // Material(elevation 0→6)，深色主题下拖拽项泛白刺眼；
                // 换成半透明黑底 + 圆角 + 边框（PiliPlus reorder_mixin
                // 思路的自定义版）。buildDefaultDragHandles 保持默认
                // （Android 即整项长按 ReorderableDelayedDragStartListener），
                // 拖拽视觉由 proxyDecorator 覆盖。
                proxyDecorator: (child, index, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => Material(
                    color: Colors.black.withValues(alpha: 0.85),
                    elevation: 4,
                    shadowColor: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: child,
                    ),
                  ),
                ),
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
                    titleAlignment: ListTileTitleAlignment.center,
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
            // 槽位全空时的空态提示
            if (enabled.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '暂无已启用动作，从下方添加',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            const Divider(height: 1, color: Colors.white12),
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
                  titleAlignment: ListTileTitleAlignment.center,
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () {
                      if (full) {
                        _toast('最多允许放 5 个');
                      } else {
                        _settings.addTopAction(a);
                      }
                    },
                    child: const Text('添加'),
                  ),
                ),
              const Divider(height: 1, color: Colors.white12),
            ],
            _PanelActionTile(
              icon: Icons.restart_alt,
              label: '重置控制栏',
              onTap: _settings.resetTopActions,
            ),
          ],
        );
      },
    );
  }

  /// 点击顶栏槽位执行动作（比例 → 弹画面比例面板；画中画 → [_enterPip]；
  /// 循环播放 → [_openLoopPanel]；听视频 → [_openAudioPlayer]；
  /// 片头片尾 → [_openIntroOutroPanel]；其余占位提示即将上线）。
  /// 倍速已移至底栏固定按钮（见底栏），不在此列。
  void _handleSlotAction(PlayerTopAction action) {
    switch (action) {
      case PlayerTopAction.aspect:
        _openFitPanel();
      case PlayerTopAction.subtitle:
        _openSubtitlePanel();
      case PlayerTopAction.audio:
        _openAudioPanel();
      case PlayerTopAction.danmaku:
        // 弹幕阶段1：顶栏槽位进入弹幕二级界面（本地/网络/自动匹配/设置）
        _openDanmakuPanel();
      case PlayerTopAction.equalizer:
        _openEqualizerPanel();
      case PlayerTopAction.decode:
        _openDecodePanel();
      case PlayerTopAction.listen:
        _openAudioPlayer();
      case PlayerTopAction.pip:
        _enterPip();
      case PlayerTopAction.loop:
        _openLoopPanel();
      case PlayerTopAction.chapter:
        _openChapterPanel();
      case PlayerTopAction.introOutro:
        _openIntroOutroPanel();
    }
  }

  /// 「更多」面板内动作对应的面板页（返回 null 表示不是面板类动作）。
  PlayerPanelPage? _panelPageFor(PlayerTopAction action) {
    switch (action) {
      case PlayerTopAction.aspect:
        return _fitPanelPage();
      case PlayerTopAction.subtitle:
        return _subtitlePanelPage();
      case PlayerTopAction.audio:
        return _audioPanelPage();
      case PlayerTopAction.danmaku:
        // 弹幕阶段1：顶栏槽位/更多均进入弹幕二级界面
        //（本地弹幕/网络弹幕/自动匹配/弹幕设置）
        return _danmakuPanelPage();
      case PlayerTopAction.loop:
        return _loopPanelPage();
      case PlayerTopAction.chapter:
        return _chapterPanelPage();
      case PlayerTopAction.introOutro:
        return _introOutroPanelPage();
      case PlayerTopAction.decode:
        return _decodePanelPage();
      case PlayerTopAction.equalizer:
        return _equalizerPanelPage();
      default:
        return null;
    }
  }

  /// 「更多」面板内点击动作：面板类 → 面板内 push（header 自动显示返回按钮，
  /// 可返回「更多」）；动作类（画中画/听视频）→ 先关闭「更多」面板再执行，
  /// 避免叠加第二个面板（§4.5 约定）。
  void _handlePanelAction(BuildContext panelContext, PlayerTopAction action) {
    final page = _panelPageFor(action);
    if (page != null) {
      PlayerPanelNavigator.of(panelContext).push(page);
      return;
    }
    switch (action) {
      case PlayerTopAction.aspect:
      case PlayerTopAction.loop:
      case PlayerTopAction.chapter:
      case PlayerTopAction.introOutro:
      case PlayerTopAction.subtitle:
      case PlayerTopAction.audio:
      case PlayerTopAction.decode:
      case PlayerTopAction.danmaku:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.equalizer:
        break; // 已在上方 _panelPageFor 分支处理
      case PlayerTopAction.listen:
        Navigator.of(panelContext).pop();
        _openAudioPlayer();
      case PlayerTopAction.pip:
        Navigator.of(panelContext).pop();
        _enterPip();
    }
  }

  /// 章节面板页（顶栏「章节」动作 / 点击章节名称共用；
  /// 无章节时面板内显示空状态提示）。
  PlayerPanelPage _chapterPanelPage() => PlayerPanelPage(
        title: '章节',
        body: PlayerChapterPanel(
          tracker: _chapterTracker,
          onSelect: (chapter) => _chapterTracker.seekToChapter(chapter),
        ),
      );

  /// 打开章节列表面板（右侧滑入，[showPlayerPanel]）。
  Future<void> _openChapterPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_chapterPanelPage()]);
    _resetHideTimer();
  }

  /// 字幕面板页（顶栏/更多「字幕」动作，工作.md 阶段1 第 3 点）：
  /// 一级面板集成字幕轨道 + 外挂导入 + 设置入口。
  PlayerPanelPage _subtitlePanelPage() => PlayerPanelPage(
        title: '字幕',
        body: Builder(
          builder: (panelContext) {
            final navigator = PlayerPanelNavigator.of(panelContext);
            return PlayerSubtitlePanel(
              controller: _subtitleController,
              onPushSubPage: (title, body) => navigator.push(
                PlayerPanelPage(title: title, body: body),
              ),
              onPopSubPage: () => navigator.pop(),
            );
          },
        ),
      );

  /// 打开字幕面板（右侧滑入，[showPlayerPanel]）。
  Future<void> _openSubtitlePanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_subtitlePanelPage()]);
    _resetHideTimer();
  }

  /// 点击跳过胶囊：跳到当前片段结束（EOF 保护见 [skipSeekTarget]），
  /// seek 离开片段后胶囊自动消失；回拖进片段可再次触发（可重复）。
  Future<void> _skipCurrentSegment() async {
    _resetHideTimer();
    await _chapterTracker.skipActiveSegment();
  }

  /// 音频面板页（顶栏/更多「音频」动作，工作.md 音频功能）：
  /// 一级面板集成音轨 + 外部音轨导入 + 音频声道 + 音频处理。
  PlayerPanelPage _audioPanelPage() => PlayerPanelPage(
        title: '音频',
        body: Builder(
          builder: (panelContext) {
            final navigator = PlayerPanelNavigator.of(panelContext);
            return PlayerAudioPanel(
              controller: _audioController,
              onPushSubPage: (title, body) => navigator.push(
                PlayerPanelPage(title: title, body: body),
              ),
              onPopSubPage: () => navigator.pop(),
            );
          },
        ),
      );

  /// 打开音频面板（右侧滑入，[showPlayerPanel]）。
  Future<void> _openAudioPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_audioPanelPage()]);
    _resetHideTimer();
  }

  /// 弹幕面板页（顶栏/更多「弹幕」动作，阶段2+3）：
  /// 二级入口列表——本地弹幕（文件选择器导入）/ 网络弹幕（弹弹Play 搜索）/
  /// 自动匹配（弹弹Play 文件匹配）/ 弹幕设置（面板内就地切换到设置页，
  /// 不叠加第二个面板，§4.5）。
  PlayerPanelPage _danmakuPanelPage() => PlayerPanelPage(
        title: '弹幕',
        body: Builder(
          builder: (panelContext) {
            final navigator = PlayerPanelNavigator.of(panelContext);
            return PlayerDanmakuPanel(
              controller: _danmakuController,
              onSettingsTap: () => navigator.push(
                const PlayerPanelPage(
                  title: '弹幕设置',
                  body: PlayerDanmakuSettingsPanel(),
                ),
              ),
              onPushSubPage: (title, body) => navigator.push(
                PlayerPanelPage(title: title, body: body),
              ),
              onPopSubPage: () => navigator.pop(),
              onNetworkTap: () => navigator.push(
                PlayerPanelPage(
                  title: '网络弹幕',
                  body: PlayerDanmakuNetworkPanel(
                    onEpisodeSelected: _onNetworkEpisodeSelected,
                  ),
                ),
              ),
              onAutoMatchTap: _autoMatchDanmaku,
            );
          },
        ),
      );

  /// 打开弹幕面板（右侧滑入，[showPlayerPanel]）。
  Future<void> _openDanmakuPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_danmakuPanelPage()]);
    _resetHideTimer();
  }

  // ── 网络弹幕 / 自动匹配（阶段3：弹弹Play 开放弹幕网络）────────

  /// 网络搜索选中某集：保存自动匹配缓存（切集自动匹配用）→ 拉取并装载。
  void _onNetworkEpisodeSelected(
    DandanAnime anime,
    DandanEpisode episode,
    String? serverUrl,
  ) {
    unawaited(_loadSelectedNetworkDanmaku(anime, episode, serverUrl));
  }

  Future<void> _loadSelectedNetworkDanmaku(
    DandanAnime anime,
    DandanEpisode episode,
    String? serverUrl,
  ) async {
    await _danmakuController.saveAutoMatchCache(
      animeId: anime.animeId,
      animeTitle: anime.animeTitle,
      serverUrl: serverUrl,
      episodes: anime.episodes,
    );
    final ok = await _danmakuController.loadNetworkDanmaku(
      episodeId: episode.episodeId,
      animeTitle: anime.animeTitle,
      episodeTitle: episode.episodeTitle,
      serverUrl: serverUrl,
    );
    if (!mounted) return;
    if (!ok) _toast('弹幕加载失败');
  }

  /// 自动匹配按钮：对当前视频文件匹配弹幕，候选唯一直接加载，多个弹选择框。
  Future<void> _autoMatchDanmaku() async {
    _toast('正在匹配弹幕，请稍候…');
    final results = await _danmakuController.matchCurrentVideo();
    if (!mounted) return;
    if (results.isEmpty) {
      _toast('未找到匹配的弹幕');
      return;
    }
    if (results.length == 1) {
      await _loadMatchedDanmaku(results.first);
      return;
    }
    await _showMatchSelectionDialog(results);
  }

  /// 加载一条自动匹配候选，并异步取回该番剧完整集列表存入缓存（切集自动匹配）。
  Future<void> _loadMatchedDanmaku(DanmakuMatchItem item) async {
    final match = item.match;
    final ok = await _danmakuController.loadNetworkDanmaku(
      episodeId: match.episodeId,
      animeTitle: match.animeTitle,
      episodeTitle: match.episodeTitle,
      serverUrl: item.serverUrl,
    );
    if (!mounted) return;
    if (!ok) {
      _toast('弹幕加载失败');
      return;
    }
    unawaited(_cacheMatchedAnime(item));
  }

  Future<void> _cacheMatchedAnime(DanmakuMatchItem item) async {
    final match = item.match;
    final episodes = await _danmakuController.fetchAnimeEpisodes(
      animeId: match.animeId,
      animeTitle: match.animeTitle,
      serverUrl: item.serverUrl,
    );
    if (episodes == null || episodes.isEmpty) return;
    await _danmakuController.saveAutoMatchCache(
      animeId: match.animeId,
      animeTitle: match.animeTitle,
      serverUrl: item.serverUrl,
      episodes: episodes,
    );
  }

  /// 自动匹配多个候选时的选择弹窗（§4.5 统一用 showAppDialog）。
  Future<void> _showMatchSelectionDialog(List<DanmakuMatchItem> results) async {
    final selected = await showAppDialog<DanmakuMatchItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择匹配结果'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in results)
                ListTile(
                  title: Text(
                    '[${item.serverName}] ${item.match.animeTitle} - '
                    '${item.match.episodeTitle}',
                  ),
                  onTap: () => Navigator.of(context).pop(item),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected != null) await _loadMatchedDanmaku(selected);
  }

  // ── 画中画 / 循环播放 / 听视频 ──────────────────────────

  /// 进入画中画小窗（顶栏「画中画」槽位）。
  ///
  /// 1. 先查设备支持（API 26+ 且系统具备 PiP 特性），不支持则提示；
  /// 2. 暂停控制层隐藏计时器并隐藏控制层（PiP 期间不显示控制）；
  /// 3. 以当前视频宽高比进入小窗（[pipAspectRatio] 约分 + 0.5–2.39 限制，
  ///    尺寸未知回退 16:9；src PipHelper 同款）；
  /// 4. media_kit 在 PiP 期间保持播放；返回前台由
  ///    [didChangeAppLifecycleState] 恢复控制层与隐藏计时。
  Future<void> _enterPip() async {
    final supported = await DeviceServices.isPipSupported();
    if (!supported) {
      _toast('当前设备不支持画中画');
      return;
    }
    _hideTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() => _controlsVisible = false);
      _controlsController.reverse();
    }
    final ratio = pipAspectRatio(
      _player.state.width ?? 0,
      _player.state.height ?? 0,
    );
    final ok = await DeviceServices.enterPip(
      aspectWidth: ratio.width,
      aspectHeight: ratio.height,
    );
    if (!ok && mounted) {
      _toast('进入画中画失败');
      _resetHideTimer();
    }
  }

  /// 循环播放面板页（顶栏/更多「循环播放」动作弹出，工作.md 第 6 点：
  /// 循环模式从设置页移入播放界面直接调整，可随自定义槽位增删）。
  PlayerPanelPage _loopPanelPage() => PlayerPanelPage(
        title: '循环播放',
        body: const PlayerLoopPanel(),
      );

  /// 打开循环播放面板（顶栏/更多「循环播放」动作）
  Future<void> _openLoopPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_loopPanelPage()]);
    _resetHideTimer();
  }

  /// 解码面板页（顶栏/更多「解码」动作弹出，四档 hwdec）
  PlayerPanelPage _decodePanelPage() => PlayerPanelPage(
        title: '解码',
        body: const PlayerDecodePanel(),
      );

  /// 打开解码面板（顶栏「解码」动作）
  Future<void> _openDecodePanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_decodePanelPage()]);
    _resetHideTimer();
  }

  /// 均衡器面板页（顶栏/更多「音频均衡器」动作弹出，工作.md 均衡器功能）：
  /// 5 频段 + 低音增强 + 虚拟环绕 + 预设，状态由 [EqualizerSettings] 全局持久化。
  PlayerPanelPage _equalizerPanelPage() =>
      const PlayerPanelPage(title: '音频均衡器', body: PlayerEqualizerPanel());

  /// 打开均衡器面板（顶栏「音频均衡器」动作）
  Future<void> _openEqualizerPanel() async {
    _hideTimer?.cancel();
    await showPlayerPanel(context, pages: [_equalizerPanelPage()]);
    _resetHideTimer();
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
      pages: [PlayerPanelPage(title: '更多', body: _buildMorePanel())],
    );
    _resetHideTimer();
  }

  /// 右下角「选择屏幕」（工作.md 第 17/18 点）：切换到竖屏播放页。
  ///
  /// v3 重构（对齐 KT 项目丝滑切换）：**横竖屏共享同一个 [Player] /
  /// [VideoController]** —— 切换只是换一个布局渲染同一路画面，**音频零中断、
  /// 无黑屏、无重新加载**。竖屏页不新建播放器、不恢复进度（同一会话），
  /// 也不负责退出时的方向/系统 UI（由本页统一恢复）。
  ///
  /// [onVideoChanged]：竖屏页切集后同步最新 path/title 给本页；
  /// [onExitPlayer]：竖屏页 EOF「自动退出」时先关竖屏页再退出本页（回到列表）。
  Future<void> _openPortraitPlayer() async {
    _hideTimer?.cancel();
    _portraitActive = true;
    // 工作.md 第 3 点：恢复进度指示器状态传给竖屏页（锁定竖屏时横屏页
    // 已完成恢复，指示器在竖屏页显示），并让竖屏页关闭时同步隐藏本页
    final resumeVisible = _resumeVisible;
    _resumeVisible = false;
    if (mounted) setState(() {});
    await Navigator.of(context).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: playerRouteName),
        transitionDuration: const Duration(milliseconds: 200),
        // 出场瞬时：竖屏页 pop 即消失（退出播放/切回横屏不再有 200ms 淡出，
        // 与主播放路由「无退出动画」保持一致）
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => PlayerPortraitPage(
          player: _player,
          controller: _controller,
          initialPath: _path,
          initialTitle: _title,
          playlist: widget.playlist,
          initialResumeVisible: resumeVisible,
          onResumeDismissed: () {
            if (!mounted) return;
            setState(() => _resumeVisible = false);
          },
          onVideoChanged: (path, title) {
            if (!mounted) return;
            setState(() {
              _path = path;
              _title = title;
              _positionNotifier.value = _player.state.position;
              _durationNotifier.value = _player.state.duration;
              _dragPositionNotifier.value = null;
            });
          },
          onExitPlayer: _exitWithPortrait,
          // 章节功能：共享横屏页跟踪器（同一 Player，状态一致）；
          // 不传则竖屏页自建空实例、章节标记/胶囊在竖屏全部不显示
          chapterTracker: _chapterTracker,
          // 片头片尾：共享横屏页跟踪器（同一 Player，状态一致）
          introOutroTracker: _introOutroTracker,
          // 字幕功能：共享横屏页控制器（同一 Player，切集后统一重新应用）
          subtitleController: _subtitleController,
          // 音频功能：共享横屏页控制器（同一 Player，切集后统一重新应用）
          audioController: _audioController,
          // 弹幕功能：共享横屏页控制器（同一 Player，渲染层 rebind）
          danmakuController: _danmakuController,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;
    _portraitActive = false;
    setState(() {});
    // 竖屏页退出时恢复了「edgeToEdge」，返回后重新应用横屏+沉浸式；
    // 播放从未中断，无需 seek/play。
    // ⚠️ 若用户是在竖屏页按返回退出整个播放器（_exitWithPortrait），
    // _exiting 已置位：这里**不能再恢复横屏**，否则会和 _exitPlayer 的
    // 竖屏恢复竞争，导致退出后列表页先横屏再竖屏（用户反馈的闪烁根因）。
    if (_exiting) return;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterFullscreen();
    _resetHideTimer();
  }

  /// 竖屏页 EOF「自动退出」/ 竖屏返回：先完成退出准备（保存进度/恢复设备/
  /// 恢复竖屏方向与系统 UI），此时竖屏页仍盖住横屏页、用户看不到底下画面；
  /// 再连续关掉竖屏页 + 横屏页（两个 pop 均无动画，直接回到列表）。
  ///
  /// ⚠️ v5 重写（用户反馈 v4 仍有「当前帧竖屏界面」闪现、黑屏淡出也嫌生硬）：
  /// 先把退出准备做完（这期间竖屏页全程在栈顶遮住横屏页），随后 `_exiting`
  /// 置黑化遮罩盖住下层横屏页，再 pop 竖屏页 + pop 横屏页——主播放路由与
  /// 竖屏页路由的出场均为瞬时（无退出动画，见 playerPageRoute），任何时刻
  /// 看不到「两层页面同框 / 半屏过渡」。
  void _exitWithPortrait() {
    if (!mounted || _exiting) return;
    _exiting = true;
    unawaited(_finishExitWithPortrait());
  }

  Future<void> _finishExitWithPortrait() async {
    if (!mounted) return;
    // 0. 下层黑化（此刻被竖屏页完全盖住，用户无感）：pop 后下层只能渲染纯黑
    setState(() => _exitBlackout = true);
    // 1. 同一帧冻结出帧：pause 后 mpv 零新帧，末帧随瞬时 pop 消失
    try {
      await _player.pause();
    } on AssertionError {
      // 播放器已销毁：静默
    }
    // 2. 旋转与 IO 并行、不阻塞 pop
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    unawaited(_saveProgress(forcePersist: true));
    unawaited(_restoreDeviceState());
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 3. 关两层：下层已是纯黑，两层 pop 任意时序都不会出现「两个竖屏界面」
    if (!mounted) return;
    Navigator.of(context).pop(); // 关竖屏页（瞬时，底下纯黑遮罩）
    if (mounted) Navigator.of(context).pop(); // 关横屏页（黑化后安全）
  }

  /// 听视频（工作.md 第 10 点）：右上角槽位/「更多 → 听视频」进入。
  ///
  /// 与竖屏页同思路：**共享同一个 [Player]**（音频零中断），听视频页只是
  /// 一个竖屏的「只播音频」界面——不新建播放器、不 open、不恢复进度。
  /// 本页打开期间 EOF 让位给听视频页（[_audioActive]），返回后恢复横屏
  /// 方向与沉浸式全屏。
  Future<void> _openAudioPlayer() async {
    _hideTimer?.cancel();
    _audioActive.value = true;
    if (mounted) setState(() {});
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return; // 防异步间隙后使用过期 context
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
          // 听视频页内切歌后同步最新 path/title 给本页
          onVideoChanged: (path, title) {
            if (!mounted) return;
            setState(() {
              _path = path;
              _title = title;
              _positionNotifier.value = _player.state.position;
              _durationNotifier.value = _player.state.duration;
              _dragPositionNotifier.value = null;
            });
          },
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;
    _audioActive.value = false;
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
    // 听视频页是竖屏，返回后恢复横屏 + 沉浸式（与竖屏页返回一致）
    final lockPortrait =
        _settings.videoOrientation == VideoOrientationMode.portrait;
    await SystemChrome.setPreferredOrientations(lockPortrait
        ? [DeviceOrientation.portraitUp]
        : [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
    _enterFullscreen();
    _resetHideTimer();
  }

  /// 底栏「列表」按钮：右侧滑入播放列表面板（工作.md 第 7 点）。
  ///
  /// 内容 = 当前视频所在文件夹的视频（从 [widget.playlist] 按同目录过滤），
  /// 面板内自带 4 排序胶囊 + 当前项高亮；点击列表项 → [_switchTo] 统一切集
  /// （自动获得进度记忆 + 新集进度恢复），面板自身随后关闭。
  Future<void> _openPlaylistPanel() async {
    _hideTimer?.cancel();
    final folder = folderOfPath(_path);
    final videos = filterVideosInFolder(widget.playlist ?? const [], folder);
    await showPlayerPanel(
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

  // ── 恢复进度 ────────────────────────────────────────────

  /// 恢复到位后显示「已恢复上次播放进度」指示器。
  ///
  /// 同步显示（无需延迟）：[PlayerResumeIndicator] 自带 300ms 进场动画，
  /// 与「揭开封层 + 开始播放」自然错峰；且在 [_applyVideoOrientation] 推入
  /// 竖屏页之前 [_resumeVisible] 已置位，锁定竖屏/竖拍视频的指示器能被
  /// [initialResumeVisible] 正确接住（v5 修复：延迟显示会导致竖屏页抢不到）。
  void _showResumeIndicator() {
    if (!mounted) return;
    setState(() => _resumeVisible = true);
  }

  /// 指示器「重头开始」：seek 0 并继续播放（指示器随后自行关闭）
  void _restartFromResume() {
    _player.seek(Duration.zero);
    _player.play();
  }

  // ── 播放完成（EOF）──────────────────────────────────────

  /// 播放完成处理：参考 kt 项目 `handleEndOfFile()` 的优先级链
  /// （单集循环 → 自动连播 → 列表循环 → 自动退出 → 自动暂停），带防重入。
  ///
  /// 防重入：[_isSwitchingVideo]（切集时 mpv 会对旧文件发 EOF 事件）与
  /// [_isHandlingEndOfFile]（completed 流重复触发）双标志；
  /// 再校验时长已知且位置已到结尾（`duration - 1s` 容差），
  /// 过滤切集瞬间的异常事件。
  void _onPlaybackCompleted() {
    // 竖屏页/听视频页打开期间：横竖屏/听视频共享同一 Player，completed
    // 由对应页面处理（本页再处理会重复切集/退出）
    if (_portraitActive || _audioActive.value) return;
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
          // 单集循环：seek 0 重播（media_kit seek 会重置 completed，可再次触发）
          _player.seek(Duration.zero);
          _player.play();
        case EndOfFileAction.playNext:
          _markCompleted();
          _playNext();
        case EndOfFileAction.playFirst:
          _markCompleted();
          _playFirst();
        case EndOfFileAction.exitPlayer:
          _markCompleted();
          _exitPlayer();
        case EndOfFileAction.pauseAtEnd:
          // 自动暂停：seek 到末尾后 pause（停在结尾）
          _markCompleted();
          _player.seek(_duration);
          _player.pause();
      }
    } finally {
      _isHandlingEndOfFile = false;
    }
  }

  /// 播放到结尾：把进度记为「已看完」（= 时长），视频列表据此显示已看完。
  /// 在切集/退出前调用（对应 src 的 `savePlaybackStateAsCompleted`）。
  void _markCompleted() {
    if (_duration <= Duration.zero) return;
    PlaybackProgressService.instance.save(_path, _duration);
  }

  // ── 退出与进度 ──────────────────────────────────────────

  /// 退出播放器：保存进度、恢复设备状态（音量/亮度）、恢复竖屏方向与
  /// 系统 UI，再 pop 回列表。
  ///
  /// ⚠️ v5 重写（用户反馈 v4：退出仍有错向界面闪现，黑屏淡出也嫌生硬）：
  /// - **不加 300ms 延时、不盖黑屏**：立即发起竖屏方向（旋转与保存/恢复
  ///   并行），随后恢复系统 UI 并立即 pop。pop 的 200ms 淡出与系统旋转
  ///   自然重叠——横屏页在淡出过程中旋转回竖屏，列表页淡入，视觉平滑；
  /// - 竖屏页路径走 [_exitWithPortrait]（先准备再连 pop 两层）。
  Future<void> _exitPlayer() async {
    if (_exiting) return;
    _exiting = true;
    // 1. 立即发起竖屏方向（不阻塞，让旋转与保存/恢复并行）
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    // 2. 同一帧冻结出帧：pause 后 mpv 零新帧（flutter#188300 不复发），
    //    末帧留在纹理上随转场消失，不再是「黑屏渐隐」
    try {
      await _player.pause();
    } on AssertionError {
      // 播放器已销毁：静默
    }
    // 3. 保存进度 + 恢复设备状态不阻塞 pop（交给后台链完成）
    unawaited(_saveProgress(forcePersist: true));
    unawaited(_restoreDeviceState());
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop();
    // 播放器销毁交给 State.dispose() 幂等兜底（_disposePlayer 保留）
  }

  /// 退出前销毁播放器：停声、停出帧、释放视频纹理（SurfaceProducer）。
  /// 幂等（widget dispose 兜底会再调一次，这里用标志防重复销毁）。
  Future<void> _disposePlayer() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    try {
      await _player.dispose();
    } on AssertionError {
      // 已被销毁（重复调用）：静默
    } catch (_) {
      // 退出路径：播放器销毁异常也不阻塞返回列表
    }
  }

  /// 记录播放进度（播了一部分才记，避免污染"没看过的视频"）。
  /// [forcePersist] = true 时强制落盘（退出/切集调用，保证重启后一定
  /// 能恢复——修复用户反馈「重启后恢复不了」的另一半根因：节流导致
  /// 磁盘上可能没有最新进度）。
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
    // 先置销毁标志：异步打开/恢复/方向流程的每个 await 之后查它并放弃
    //（risk_audit #2，防止恢复流程对已销毁播放器 seek 抛异常写假崩溃日志）
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
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
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _dragPositionNotifier.dispose();
    _chapterTracker.dispose();
    _subtitleController.dispose();
    _audioController.dispose();
    _danmakuController.dispose();
    _audioActive.dispose();
    _thumbHideTimer?.cancel();
    _cancelThumbPrefetch();
    // 兜底保存进度（正常退出已走 _exitPlayer 的强制落盘，这里防异常路径；
    // dispose 无法 await，交给后台链串行完成）
    _saveProgress();
    // 兜底恢复设备状态（正常退出已走 _exitPlayer，这里防异常路径泄漏）
    _restoreDeviceState();
    DeviceServices.clearFrameCache();
    // 退出时强制恢复竖屏和系统 UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 兜底销毁播放器（正常退出已先 pause 冻结出帧，这里销毁释放纹理；
    // 幂等，不会重复销毁）
    unawaited(_disposePlayer());
    super.dispose();
  }

  String _fmt(Duration d) => formatDuration(d.inMilliseconds);

  /// 时间文本显示模式：false =「已播/总时长」；true =「已播/剩余时长」
  /// （工作.md 第 20 点，点击底栏时间文本切换）
  bool _showRemainingTime = false;

  /// 底栏时间文本：「已播/总时长」⇄「已播/剩余时长」（剩余 = 总 - 已播，
  /// 负值清零为 -00:00，避免拖动越过结尾时出现正数）
  String get _timeText {
    final pos = _dragPosition ?? _position;
    final total = _duration;
    if (_showRemainingTime && total > Duration.zero) {
      final remaining = total - pos;
      final r = remaining.isNegative ? Duration.zero : remaining;
      return '${_fmt(pos)} / -${_fmt(r)}';
    }
    return '${_fmt(pos)} / ${_fmt(total)}';
  }

  /// 点击底栏时间文本：切换显示模式
  void _toggleTimeMode() {
    setState(() => _showRemainingTime = !_showRemainingTime);
    _resetHideTimer();
  }

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
                // 外层 Transform 承载双指缩放/平移）。
                // 用 ListenableBuilder 监听设置：画面比例面板（独立弹窗路由）
                // 修改 videoFit 后这里实时重建，无需关掉面板才生效
                //（工作.md 第 8 点 bug 修复）。
                // ⚠️ key 必须随 fit 变化（工作.md 第 3 点：4:3 → 自动失效的根因）：
                // media_kit Video 是 StatefulWidget，fit/aspectRatio 变化时若不
                // 换 key，内部渲染纹理的尺寸缓存不会重建，导致「从 4:3 切回自动
                // 仍保持 4:3」——用 ValueKey(fit) 强制重建 Video。
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_settings, _audioActive]),
                    builder: (context, _) => Transform(
                      transform: _zoomMatrix(),
                      child: Video(
                        key: ValueKey('fit-${_settings.videoFit.index}'),
                        controller: _controller,
                        controls: NoVideoControls,
                        fit: _settings.videoFit.boxFit,
                        aspectRatio: _settings.videoFit.aspectRatio,
                        // 听视频页打开期间退后台不暂停（后台播放）；否则保持
                        // 默认「退后台暂停」。
                        pauseUponEnteringBackgroundMode: !_audioActive.value,
                      ),
                    ),
                  ),
                ),
                // 弹幕层（弹幕移植方案阶段1）：视频层与手势层之间；
                // DanmakuScreen 内部自带 IgnorePointer 不拦截手势；
                // 与视频缩放 Transform 无关（弹幕铺满整个播放区域）
                Positioned.fill(
                  child: PlayerDanmakuLayer(controller: _danmakuController),
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
                // 顶栏顶部下落 / 底栏底部上升 / 右侧操作右侧滑入（Kazumi 风格）。
                // 顶部为「时间/电量信息行（工作.md 第 12 点）+ 顶栏」两段，
                // 信息行轻量提示、字号小于标题，整体随控制层一起滑入滑出。
                // ⚠️ 顶部渐变压暗统一放在这里（信息行 + 顶栏整体一个连续
                // 渐变：顶部最暗 → 向下淡出）。各组件不再各自画渐变，
                // 否则两段渐变拼接会在时间/电量行下方出现暗色断层
                // （用户反馈 v2：阴影位置不正确、割裂感）。
                IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: SlideTransition(
                    position: _topSlide,
                    child: Align(
                      alignment: Alignment.topCenter,
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
                            PlayerStatusBar(
                              isOnlinePlayback: isOnlineMedia(_path),
                            ),
                            PlayerTopBar(                            title: _title,
                              onBack: _exitPlayer,
                              onMore: _openMorePanel,
                              onActionTap: _handleSlotAction,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 跳过胶囊浮层 + 底栏主体：胶囊贴底栏顶部（章节名称上方），
                // 独立于底栏滑出动画（自动弹出期间控制层隐藏也可见）。
                // ⚠️ 必须 Positioned 钉在底部：Stack 非 Positioned 子项
                // 默认摆放到 topLeft，底栏会整个跑到屏幕顶部（错位 bug）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 跳过胶囊（工作.md 第 4 点）：进入 OP/ED 等片段自动弹出
                      // （5 秒倒计时自动消失）；控制层可见且仍在片段内时常驻；
                      // 回拖进片段可重复触发。位置与章节名称行同左缘对齐。
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
                            duration: const Duration(milliseconds: 250),
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
                                        onTap: _skipCurrentSegment,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        ignoring: !_controlsVisible || _locked,
                        child: SlideTransition(
                          position: _bottomSlide,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            // 局部订阅进度 + 章节 + 弹幕开关：位置/时长/章节
                            // 变化只重建底栏（进度条 + 时间文本 + 章节标记 +
                            // 弹幕图标），不重建整页（risk_audit #1）
                            child: ListenableBuilder(
                              listenable: _bottomBarListenable,
                              builder: (context, _) => PlayerBottomBar(
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
                                  _player.seek(Duration(milliseconds: v.round()));
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
                                onTimeTap: _toggleTimeMode,
                                onSpeedTap: _openSpeedPanel,
                                showSpeedButtonBackground:
                                    _settings.showButtonBackground,
                                superResolutionLabel: '超分辨率',
                                onSuperResolutionTap: _openSuperResolutionPanel,
                                onScreenSwitchTap: _openPortraitPlayer,
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
                                onChapterTap: _openChapterPanel,
                                // 弹幕功能（阶段1）：开关 + 设置按钮，
                                // 位于时间文本右侧（工作.md 弹幕第 5 点）
                                danmakuOn: _danmakuController.danmakuOn,
                                onDanmakuToggle: _toggleDanmaku,
                                onDanmakuSettingsTap: _openDanmakuSettingsPanel,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                // 进度条拖动缩略图预览（进度条上方跟随拖动位置；
                // 松手淡出后再卸载）
                if (_thumbPreview != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 104,
                    child: PlayerThumbnailPreview(
                      frame: _thumbPreview!.frame,
                      time: _thumbPreview!.time,
                      fraction: _thumbFraction,
                      visible: _thumbVisible,
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
                // 常驻进度线（设置开启且控制层隐藏时显示；锁定后不显示）。
                // 内部局部订阅进度（risk_audit #1）：位置变化只重画这条线，
                // 不重建整页；时长未知时先渲染空位（时长就绪后自动出现）。
                if (_settings.showProgressLine && !_controlsVisible && !_locked)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2.5,
                    child: IgnorePointer(
                      child: ListenableBuilder(
                        listenable: _progressListenable,
                        builder: (context, _) {
                          if (_duration <= Duration.zero) {
                            return const SizedBox.shrink();
                          }
                          return Align(
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
                          );
                        },
                      ),
                    ),
                  ),
                // 恢复进度指示器（横屏顶部弹出，独立于控制层显隐；z 序最顶）。
                // 工作.md 第 2 点：出现位置上移、靠近横屏状态下顶部（原 top: 64
                // 在顶栏下方，现提到顶部信息行/顶栏区域下方的 top: 20 附近）。
                if (_resumeVisible)
                  Positioned(
                    // 稳定 key：拖动进度条时缩略图气泡（前一个条件 Positioned）
                    // 会插入/移出 Stack children，无 key 兄弟项按索引错位匹配
                    // 会重建 State → 指示器进场动画重播（「拖动一下唤出一次」根因）
                    key: const ValueKey('resumeIndicator'),
                    left: 0,
                    right: 0,
                    top: 20,
                    child: Center(
                      child: PlayerResumeIndicator(
                        onRestart: _restartFromResume,
                        onClose: () {
                          if (mounted) {
                            setState(() => _resumeVisible = false);
                          }
                        },
                      ),
                    ),
                  ),
                // 恢复进度封层（z 序最顶）：暂停加载 + seek 期间盖住视频，
                // 用户看不到 mpv 暂停态渲染的 0 时刻第一帧海报；位置确认
                // 到位后揭开（_restoring 置 false）+ 播放，首帧即目标帧。
                // 用一个小转圈提示「正在恢复」，避免纯黑让用户以为卡死。
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
                // 退出黑化遮罩（z 序最顶）：竖屏退出期间盖住整个横屏页
                // （视频 + UI 骨架），保证两层页面任何时刻不同框
                if (_exitBlackout)
                  const Positioned.fill(
                    child: ColoredBox(color: Colors.black),
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
      titleAlignment: ListTileTitleAlignment.center,
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
