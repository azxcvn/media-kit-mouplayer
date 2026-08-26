import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/player_loop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器控制设置：右上角「更多」面板的启用动作、双击手势、快进/快退时长、
/// 常驻进度线、倍速记忆、自定义倍速预设、控制按钮背景、画面比例、
/// 长按倍速（倍率/指示器开关/首次提示）、音量亮度手势（灵敏度/保存到系统）、
/// 双指缩放、已观看进度阈值、自动连播/自动退出/循环播放模式。
///
/// 全局单例（同 [PlaybackProgressService] 模式），ChangeNotifier + shared_preferences
/// 持久化；播放页与「播放器设置」子页共同监听。
class PlayerControlsSettings extends ChangeNotifier {
  static final PlayerControlsSettings instance = PlayerControlsSettings._();

  PlayerControlsSettings._();

  /// 加载去重（risk_audit #9）：setter 在改设置前 await [ensureLoaded]，
  /// 防止启动时异步 load 尚未完成、用户已改设置被 load 覆盖（与
  /// [PlaybackProgressService.ensureLoaded] 同一防护；load 本身可重复调用，
  /// 供测试模拟重启重新读盘）。
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyTopActions = 'player_controls_top_actions';
  static const _keyDoubleTapMode = 'player_controls_double_tap_mode';
  static const _keyProgressLine = 'player_controls_progress_line';
  static const _keyRememberSpeed = 'player_controls_remember_speed';
  static const _keyLastSpeed = 'player_controls_last_speed';
  static const _keySeek = 'player_controls_seek';
  static const _keyCustomSpeedPresets = 'player_controls_custom_speed_presets';
  static const _keyButtonBackground = 'player_controls_button_background';
  static const _keyVideoFit = 'player_controls_video_fit';
  // 手势 / 音量亮度 / 长按倍速
  static const _keyLongPressSpeed = 'player_controls_long_press_speed';
  static const _keyShowSpeedIndicator = 'player_controls_show_speed_indicator';
  static const _keySpeedHintShown = 'player_controls_speed_hint_shown';
  static const _keySaveVolumeToSystem = 'player_controls_save_volume_system';
  static const _keyVolumeSensitivity = 'player_controls_volume_sensitivity';
  static const _keyBrightnessSensitivity =
      'player_controls_brightness_sensitivity';
  static const _keyEnableShrinkVideo = 'player_controls_enable_shrink_video';
  static const _keyShowThumbnailPreview =
      'player_controls_show_thumbnail_preview';
  static const _keyWatchThreshold = 'player_controls_watch_threshold';
  // v2：自动连播 / 播放完毕自动退出 / 循环播放模式
  static const _keyAutoNext = 'player_controls_auto_next';
  static const _keyAutoExit = 'player_controls_auto_exit';
  static const _keyLoopMode = 'player_controls_loop_mode';
  // 视频方向（自动/锁定竖屏/锁定横屏）+ 播放界面动画开关
  static const _keyVideoOrientation = 'player_controls_video_orientation';
  static const _keyPlayerAnimations = 'player_controls_player_animations';
  // 播放界面顶部信息栏（工作.md 阶段1 第 1 点：时间/电量/网速/数据类型多选）
  static const _keyShowTopTime = 'player_controls_show_top_time';
  static const _keyShowTopBattery = 'player_controls_show_top_battery';
  static const _keyShowTopNetSpeed = 'player_controls_show_top_net_speed';
  static const _keyShowTopNetType = 'player_controls_show_top_net_type';
  // 旧版顶部信息单选枚举 key（仅用于一次性迁移到新多选）
  static const _keyTopStatusDisplay = 'player_controls_top_status_display';
  // 章节功能：进度条章节标记（默认开启，工作.md 章节功能）
  static const _keyShowChapterProgress =
      'player_controls_show_chapter_progress';

  // 旧版按键时长 key（v1 拆分过双击/按钮两套，现已合并），仅用于数据迁移
  static const _legacyKeyButtonSeek = 'player_controls_button_seek';

  /// 「更多」面板中可启用的动作数量上限
  static const int maxTopActions = 5;

  /// 快进/快退时长上限（秒）
  static const int maxSeekSeconds = 600;

  /// 自定义倍速预设数量上限
  static const int maxCustomSpeedPresets = 8;

  /// 倍速有效范围
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;

  /// 长按倍速：设置内可调范围 1.0 – 4.0，步进 0.5（离散，工作.md 阶段1 第 4 点）
  static const double minLongPressSpeed = 1.0;
  static const double maxLongPressSpeed = 4.0;

  /// 长按倍速步进（0.5，离散档位：1.0 / 1.5 / 2.0 / 2.5 / 3.0 / 3.5 / 4.0）
  static const double longPressSpeedStep = 0.5;

  /// 长按期间左右滑动临时调速的范围：1.5 – 4.0，间隔 0.5（离散档位）
  static const double minDynamicSpeed = 1.5;
  static const double maxDynamicSpeed = 4.0;
  static const double dynamicSpeedStep = 0.5;

  /// 音量/亮度手势灵敏度范围（倍率，默认 1.0 = 满屏滑动走满整个量程）
  static const double minGestureSensitivity = 0.5;
  static const double maxGestureSensitivity = 2.0;
  static const double defaultGestureSensitivity = 1.0;

  /// 「已观看」进度阈值范围与步进（5% – 100%，步进 5%，默认 95%）
  static const double minWatchThreshold = 0.05;
  static const double maxWatchThreshold = 1.0;
  static const double watchThresholdStep = 0.05;

  List<PlayerTopAction> _topActions = const [];
  DoubleTapMode _doubleTapMode = DoubleTapMode.pause;
  bool _showProgressLine = false;
  bool _rememberSpeed = false;
  double _lastSpeed = 1.0;
  int _seekSeconds = 10;
  List<double> _customSpeedPresets = const [];

  /// 播放控制按钮背景（默认关闭）：开启后底栏倍速图标与顶栏控制图标
  /// 显示半透明圆角背景
  bool _showButtonBackground = false;

  /// 画面比例（默认自动 contain）
  PlayerVideoFit _videoFit = PlayerVideoFit.contain;

  /// 长按倍速（设置内 1.0 – 6.0，默认 2.0）
  double _longPressSpeed = 2.0;

  /// 长按倍速播放指示器开关（默认开启）
  bool _showSpeedIndicator = true;

  /// 是否已完成过完整的「长按 + 左右滑动」操作（首次使用提示只显示一次）
  bool _speedHintShown = false;

  /// 播放时调整的音量在退出后是否写回系统（默认开启；关闭则恢复进入前音量）
  bool _saveVolumeToSystem = true;

  /// 音量手势灵敏度（满屏滑动对应的音量变化倍率，0.5 – 2.0，默认 1.0）
  double _volumeSensitivity = defaultGestureSensitivity;

  /// 亮度手势灵敏度（同上，默认 1.0）
  double _brightnessSensitivity = defaultGestureSensitivity;

  /// 双指缩小视频（默认开启：最小缩放 0.75；关闭则最小 1.0）
  bool _enableShrinkVideo = true;

  /// 进度条缩略图预览（默认开启：FFmpeg 硬解快速抓帧 ~85ms/帧，
  /// 独立解码实例与播放并行，拖动进度条时显示画面预览）
  bool _showThumbnailPreview = true;

  /// 「已观看」达成阈值（5% – 100%，步进 5%，默认 95%）：
  /// 视频列表「进度」字段据此把视频判定为 未观看 / 观看中 / 已看完
  double _watchThreshold = 0.95;

  /// 自动连播：当前视频播完后自动播放下一集（默认开启）
  bool _autoNext = true;

  /// 播放完毕自动退出：当前文件夹最后一个视频播完后自动退出播放页
  /// （默认开启；关闭则播完自动暂停停在末尾）
  bool _autoExit = true;

  /// 循环播放模式（默认关闭）
  LoopMode _loopMode = LoopMode.off;

  /// 视频方向（默认自动：按视频方向横/竖屏播放）
  VideoOrientationMode _videoOrientation = VideoOrientationMode.auto;

  /// 播放界面动画（默认开启）：关闭后控制层/面板等不再显示进出场动画
  bool _playerAnimations = true;

  /// 播放界面顶部信息栏多选开关（工作.md 阶段1 第 1 点，默认四项全选）：
  /// 时间 / 电量 / 网速详情 / 数据类型（WiFi/移动数据图标）。
  bool _showTopTime = true;
  bool _showTopBattery = true;
  bool _showTopNetSpeed = true;
  bool _showTopNetType = true;

  /// 显示章节进度条（默认开启）：进度条上标记章节节点、显示当前章节名称
  bool _showChapterProgress = true;

  /// 右上角槽位上已放置的动作（有序，最多 [maxTopActions] 个；空列表 = 槽位全空）
  List<PlayerTopAction> get topActions => List.unmodifiable(_topActions);
  DoubleTapMode get doubleTapMode => _doubleTapMode;
  bool get showProgressLine => _showProgressLine;
  bool get rememberSpeed => _rememberSpeed;
  double get lastSpeed => _lastSpeed;
  int get seekSeconds => _seekSeconds;
  List<double> get customSpeedPresets => List.unmodifiable(_customSpeedPresets);
  bool get showButtonBackground => _showButtonBackground;
  PlayerVideoFit get videoFit => _videoFit;
  double get longPressSpeed => _longPressSpeed;
  bool get showSpeedIndicator => _showSpeedIndicator;
  bool get speedHintShown => _speedHintShown;
  bool get saveVolumeToSystem => _saveVolumeToSystem;
  double get volumeSensitivity => _volumeSensitivity;
  double get brightnessSensitivity => _brightnessSensitivity;
  bool get enableShrinkVideo => _enableShrinkVideo;
  bool get showThumbnailPreview => _showThumbnailPreview;
  double get watchThreshold => _watchThreshold;
  bool get autoNext => _autoNext;
  bool get autoExit => _autoExit;
  LoopMode get loopMode => _loopMode;
  VideoOrientationMode get videoOrientation => _videoOrientation;
  bool get playerAnimations => _playerAnimations;
  bool get showTopTime => _showTopTime;
  bool get showTopBattery => _showTopBattery;
  bool get showTopNetSpeed => _showTopNetSpeed;
  bool get showTopNetType => _showTopNetType;
  bool get showChapterProgress => _showChapterProgress;

  /// 启动时加载（main.dart 调用）
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _topActions = (prefs.getStringList(_keyTopActions) ?? const [])
        .map(PlayerTopAction.byId)
        .whereType<PlayerTopAction>()
        .toList();
    // 空列表是合法状态（槽位全空），不做回退
    final mode = prefs.getInt(_keyDoubleTapMode);
    if (mode != null && mode >= 0 && mode < DoubleTapMode.values.length) {
      _doubleTapMode = DoubleTapMode.values[mode];
    }
    _showProgressLine = prefs.getBool(_keyProgressLine) ?? false;
    _showChapterProgress = prefs.getBool(_keyShowChapterProgress) ?? true;
    // 记忆倍速默认关闭（用户显式开启后才记住上次倍速）
    _rememberSpeed = prefs.getBool(_keyRememberSpeed) ?? false;
    _lastSpeed = prefs.getDouble(_keyLastSpeed) ?? 1.0;
    _showButtonBackground =
        prefs.getBool(_keyButtonBackground) ?? false;
    final fit = prefs.getInt(_keyVideoFit);
    if (fit != null && fit >= 0 && fit < PlayerVideoFit.values.length) {
      _videoFit = PlayerVideoFit.values[fit];
    }
    // 新 key 优先；兼容旧版按钮时长（v1 拆分，现合并为单一时长）
    _seekSeconds = (prefs.getInt(_keySeek) ??
            prefs.getInt(_legacyKeyButtonSeek) ??
            10)
        .clamp(1, maxSeekSeconds);
    _customSpeedPresets = (prefs.getStringList(_keyCustomSpeedPresets) ??
            const [])
        .map(double.tryParse)
        .whereType<double>()
        .where((v) => v >= minSpeed && v <= maxSpeed)
        .toList();
    // 长按倍速：范围 1.0 – 4.0、步进 0.5（工作.md 阶段1 第 4 点）。旧版本以 0.1 粒度、
    // 上限 6.0 保存，读入后先钳制再就近对齐 0.5 档位（如 4.6 → 4.0，2.3 → 2.5）
    _longPressSpeed = _roundLongPressSpeed(
      prefs.getDouble(_keyLongPressSpeed) ?? 2.0,
    ).clamp(minLongPressSpeed, maxLongPressSpeed);
    _showSpeedIndicator = prefs.getBool(_keyShowSpeedIndicator) ?? true;
    _speedHintShown = prefs.getBool(_keySpeedHintShown) ?? false;
    _saveVolumeToSystem = prefs.getBool(_keySaveVolumeToSystem) ?? true;
    _volumeSensitivity = (prefs.getDouble(_keyVolumeSensitivity) ??
            defaultGestureSensitivity)
        .clamp(minGestureSensitivity, maxGestureSensitivity);
    _brightnessSensitivity = (prefs.getDouble(_keyBrightnessSensitivity) ??
            defaultGestureSensitivity)
        .clamp(minGestureSensitivity, maxGestureSensitivity);
    _enableShrinkVideo = prefs.getBool(_keyEnableShrinkVideo) ?? true;
    // 进度条缩略图预览：默认开启（FFmpeg 硬解快速引擎，开销极低）
    _showThumbnailPreview =
        prefs.getBool(_keyShowThumbnailPreview) ?? true;
    // 旧值迁移：老版本以 1% 粒度存（0.5 – 1.0），读入后钳制到 5% – 100%
    // 并就近对齐到 5% 档位
    _watchThreshold = _roundWatchThreshold(
      prefs.getDouble(_keyWatchThreshold) ?? 0.95,
    ).clamp(minWatchThreshold, maxWatchThreshold);
    _autoNext = prefs.getBool(_keyAutoNext) ?? true;
    _autoExit = prefs.getBool(_keyAutoExit) ?? true;
    final loop = prefs.getInt(_keyLoopMode);
    if (loop != null && loop >= 0 && loop < LoopMode.values.length) {
      _loopMode = LoopMode.values[loop];
    }
    final orientation = prefs.getInt(_keyVideoOrientation);
    if (orientation != null &&
        orientation >= 0 &&
        orientation < VideoOrientationMode.values.length) {
      _videoOrientation = VideoOrientationMode.values[orientation];
    }
    _playerAnimations = prefs.getBool(_keyPlayerAnimations) ?? true;
    // 顶部信息多选（工作.md 阶段1 第 1 点）：新 key 优先；无新 key 时从旧单选枚举
    // 迁移时间/电量两项，网速/数据类型默认开启。
    final migrated = _migrateTopStatus(prefs.getInt(_keyTopStatusDisplay));
    _showTopTime = prefs.getBool(_keyShowTopTime) ?? migrated.$1;
    _showTopBattery = prefs.getBool(_keyShowTopBattery) ?? migrated.$2;
    _showTopNetSpeed = prefs.getBool(_keyShowTopNetSpeed) ?? true;
    _showTopNetType = prefs.getBool(_keyShowTopNetType) ?? true;
    notifyListeners();
  }

  /// 从旧版顶部信息单选枚举（0=关闭 1=时间 2=电量 3=两者）迁移出时间/电量的初始勾选。
  /// 无旧值时默认时间+电量均勾选（与旧默认 both 一致）。
  static (bool, bool) _migrateTopStatus(int? old) {
    return switch (old) {
      0 => (false, false),
      1 => (true, false),
      2 => (false, true),
      3 => (true, true),
      _ => (true, true),
    };
  }

  Future<void> setDoubleTapMode(DoubleTapMode v) async {
    await ensureLoaded();
    if (_doubleTapMode == v) return;
    _doubleTapMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDoubleTapMode, v.index);
  }

  Future<void> setShowProgressLine(bool v) async {
    await ensureLoaded();
    if (_showProgressLine == v) return;
    _showProgressLine = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProgressLine, v);
  }

  /// 显示章节进度条开关（默认开启）：进度条章节节点标记 + 当前章节名称
  Future<void> setShowChapterProgress(bool v) async {
    await ensureLoaded();
    if (_showChapterProgress == v) return;
    _showChapterProgress = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowChapterProgress, v);
  }

  /// 播放控制按钮背景开关（默认关闭）
  Future<void> setShowButtonBackground(bool v) async {
    await ensureLoaded();
    if (_showButtonBackground == v) return;
    _showButtonBackground = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyButtonBackground, v);
  }

  /// 画面比例（拉伸/自动/裁剪/等宽/等高/原始/限制/4:3/16:9）
  Future<void> setVideoFit(PlayerVideoFit v) async {
    await ensureLoaded();
    if (_videoFit == v) return;
    _videoFit = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVideoFit, v.index);
  }

  Future<void> setRememberSpeed(bool v) async {
    await ensureLoaded();
    if (_rememberSpeed == v) return;
    _rememberSpeed = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberSpeed, v);
  }

  /// 记录当前倍速（无论是否启用记忆都会保存；启用记忆后下次打开生效）
  Future<void> setSpeed(double v) async {
    await ensureLoaded();
    _lastSpeed = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLastSpeed, v);
  }

  /// 快进/快退时长（秒），限制在 1 – maxSeekSeconds。双击手势与中央按钮共用。
  Future<void> setSeekSeconds(int v) async {
    await ensureLoaded();
    final clamped = v.clamp(1, maxSeekSeconds);
    if (_seekSeconds == clamped) return;
    _seekSeconds = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeek, clamped);
  }

  /// 长按倍速（1.0 – 4.0，步进 0.5，离散）。任意输入就近对齐到 0.5 档位并钳制范围。
  Future<void> setLongPressSpeed(double v) async {
    await ensureLoaded();
    final clamped = _roundLongPressSpeed(v)
        .clamp(minLongPressSpeed, maxLongPressSpeed);
    if ((_longPressSpeed - clamped).abs() < 0.001) return;
    _longPressSpeed = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLongPressSpeed, clamped);
  }

  /// 按 0.5 步进取整到最近档位（避免浮点误差，与 load 迁移同一对齐逻辑）
  static double _roundLongPressSpeed(double v) {
    return (v / longPressSpeedStep).round() * longPressSpeedStep;
  }

  /// 倍速播放指示器开关（长按倍速时是否显示「正在 X.Xx 倍速播放」）
  Future<void> setShowSpeedIndicator(bool v) async {
    await ensureLoaded();
    if (_showSpeedIndicator == v) return;
    _showSpeedIndicator = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowSpeedIndicator, v);
  }

  /// 标记「已完成一次完整的长按 + 左右滑动」，首次使用提示不再出现
  Future<void> markSpeedHintShown() async {
    await ensureLoaded();
    if (_speedHintShown) return;
    _speedHintShown = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpeedHintShown, true);
  }

  /// 播放时调整的音量是否在退出后写回系统（默认开启）
  Future<void> setSaveVolumeToSystem(bool v) async {
    await ensureLoaded();
    if (_saveVolumeToSystem == v) return;
    _saveVolumeToSystem = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveVolumeToSystem, v);
  }

  /// 音量手势灵敏度（满屏滑动对应的量程倍率，0.5 – 2.0）
  Future<void> setVolumeSensitivity(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minGestureSensitivity, maxGestureSensitivity);
    if ((_volumeSensitivity - clamped).abs() < 0.001) return;
    _volumeSensitivity = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolumeSensitivity, clamped);
  }

  /// 亮度手势灵敏度（同上）
  Future<void> setBrightnessSensitivity(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minGestureSensitivity, maxGestureSensitivity);
    if ((_brightnessSensitivity - clamped).abs() < 0.001) return;
    _brightnessSensitivity = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBrightnessSensitivity, clamped);
  }

  /// 双指缩小视频（默认开启：最小缩放 0.75；关闭则最小 1.0）
  Future<void> setEnableShrinkVideo(bool v) async {
    await ensureLoaded();
    if (_enableShrinkVideo == v) return;
    _enableShrinkVideo = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableShrinkVideo, v);
  }

  /// 进度条缩略图预览开关（默认开启：FFmpeg 硬解快速引擎，开销极低）
  Future<void> setShowThumbnailPreview(bool v) async {
    await ensureLoaded();
    if (_showThumbnailPreview == v) return;
    _showThumbnailPreview = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowThumbnailPreview, v);
  }

  /// 「已观看」达成阈值（5% – 100%，步进 5%，默认 95%）：
  /// 进度 >= 阈值 → 已看完（列表灰色）；>0 且 < 阈值 → 观看中。
  /// 任意输入就近对齐到 5% 档位并钳制范围（与 load 迁移同一对齐逻辑）。
  Future<void> setWatchThreshold(double v) async {
    await ensureLoaded();
    final clamped = _roundWatchThreshold(v)
        .clamp(minWatchThreshold, maxWatchThreshold);
    if ((_watchThreshold - clamped).abs() < 0.0001) return;
    _watchThreshold = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWatchThreshold, clamped);
  }

  /// 按 5%（0.05）步进取整到最近档位：
  /// 百分数除以 5 取整后乘回，避免浮点误差（如 0.95 不偏移成 0.9500000000000001）
  static double _roundWatchThreshold(double v) {
    final percent = v * 100;
    final steps = (percent / 5).round();
    return steps * 5 / 100;
  }

  /// 自动连播：当前视频播完后自动播放下一集（默认开启）
  Future<void> setAutoNext(bool v) async {
    await ensureLoaded();
    if (_autoNext == v) return;
    _autoNext = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoNext, v);
  }

  /// 播放完毕自动退出：当前文件夹最后一个视频播完后自动退出播放页
  /// （默认开启；关闭则播完自动暂停停在末尾）
  Future<void> setAutoExit(bool v) async {
    await ensureLoaded();
    if (_autoExit == v) return;
    _autoExit = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoExit, v);
  }

  /// 循环播放模式（默认关闭；off / 列表循环 / 单集循环）
  Future<void> setLoopMode(LoopMode v) async {
    await ensureLoaded();
    if (_loopMode == v) return;
    _loopMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLoopMode, v.index);
  }

  /// 视频方向（默认自动：按视频方向横/竖屏；锁定竖屏/横屏强制对应方向）
  Future<void> setVideoOrientation(VideoOrientationMode v) async {
    await ensureLoaded();
    if (_videoOrientation == v) return;
    _videoOrientation = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVideoOrientation, v.index);
  }

  /// 播放界面动画开关（默认开启；关闭后播放页控制层与面板直接出现/消失）
  Future<void> setPlayerAnimations(bool v) async {
    await ensureLoaded();
    if (_playerAnimations == v) return;
    _playerAnimations = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPlayerAnimations, v);
  }

  /// 播放界面顶部信息栏：时间/电量/网速/数据类型四项多选开关（工作.md 阶段1 第 1 点）
  Future<void> setShowTopTime(bool v) => _setTopFlag(_keyShowTopTime, v, (x) => _showTopTime = x, _showTopTime);
  Future<void> setShowTopBattery(bool v) => _setTopFlag(_keyShowTopBattery, v, (x) => _showTopBattery = x, _showTopBattery);
  Future<void> setShowTopNetSpeed(bool v) => _setTopFlag(_keyShowTopNetSpeed, v, (x) => _showTopNetSpeed = x, _showTopNetSpeed);
  Future<void> setShowTopNetType(bool v) => _setTopFlag(_keyShowTopNetType, v, (x) => _showTopNetType = x, _showTopNetType);

  Future<void> _setTopFlag(
    String key,
    bool v,
    void Function(bool) assign,
    bool current,
  ) async {
    await ensureLoaded();
    if (current == v) return;
    assign(v);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  /// 添加自定义倍速预设（去重、限制范围与数量）
  Future<void> addCustomSpeedPreset(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minSpeed, maxSpeed);
    if (_customSpeedPresets.any((e) => (e - clamped).abs() < 0.01)) return;
    if (_customSpeedPresets.length >= maxCustomSpeedPresets) return;
    _customSpeedPresets = [..._customSpeedPresets, clamped];
    notifyListeners();
    await _saveCustomSpeedPresets();
  }

  Future<void> removeCustomSpeedPreset(double v) async {
    await ensureLoaded();
    if (!_customSpeedPresets.any((e) => (e - v).abs() < 0.01)) return;
    _customSpeedPresets = [
      for (final e in _customSpeedPresets)
        if ((e - v).abs() >= 0.01) e,
    ];
    notifyListeners();
    await _saveCustomSpeedPresets();
  }

  /// 倍速预设重置：清空自定义预设，回到系统预设
  Future<void> resetCustomSpeedPresets() async {
    await ensureLoaded();
    if (_customSpeedPresets.isEmpty) return;
    _customSpeedPresets = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCustomSpeedPresets);
  }

  Future<void> _saveCustomSpeedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyCustomSpeedPresets,
      _customSpeedPresets.map((v) => v.toStringAsFixed(2)).toList(),
    );
  }

  /// 放置动作到槽位（不重复、不超过上限；放满后需先移除）
  Future<void> addTopAction(PlayerTopAction a) async {
    await ensureLoaded();
    if (_topActions.contains(a) || _topActions.length >= maxTopActions) return;
    _topActions = [..._topActions, a];
    notifyListeners();
    await _saveTopActions();
  }

  Future<void> removeTopAction(PlayerTopAction a) async {
    await ensureLoaded();
    if (!_topActions.contains(a)) return;
    _topActions = [..._topActions]..remove(a);
    notifyListeners();
    await _saveTopActions();
  }

  /// 槽位排序。配合 ReorderableListView 的 [onReorderItem] 使用：
  /// 该回调已按「移除后插入」修正 newIndex，这里直接 removeAt + insert。
  Future<void> reorderTopAction(int oldIndex, int newIndex) async {
    await ensureLoaded();
    if (oldIndex == newIndex) return;
    final list = [..._topActions];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _topActions = list;
    notifyListeners();
    await _saveTopActions();
  }

  /// 控制栏重置：清空全部槽位（默认状态 = 槽位全空，仅保留「更多」）
  Future<void> resetTopActions() async {
    await ensureLoaded();
    if (_topActions.isEmpty) return;
    _topActions = const [];
    notifyListeners();
    await _saveTopActions();
  }

  Future<void> _saveTopActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyTopActions,
      _topActions.map((e) => e.id).toList(),
    );
  }

  /// 测试用：恢复默认值（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void reset() {
    _loadFuture = null; // 下次 setter 重新触发 load（读当前 mock prefs）
    _topActions = const [];
    _doubleTapMode = DoubleTapMode.pause;
    _showProgressLine = false;
    _rememberSpeed = false;
    _lastSpeed = 1.0;
    _seekSeconds = 10;
    _customSpeedPresets = const [];
    _showButtonBackground = false;
    _videoFit = PlayerVideoFit.contain;
    _longPressSpeed = 2.0;
    _showSpeedIndicator = true;
    _speedHintShown = false;
    _saveVolumeToSystem = true;
    _volumeSensitivity = defaultGestureSensitivity;
    _brightnessSensitivity = defaultGestureSensitivity;
    _enableShrinkVideo = true;
    _showThumbnailPreview = true;
    _watchThreshold = 0.95;
    _autoNext = true;
    _autoExit = true;
    _loopMode = LoopMode.off;
    _videoOrientation = VideoOrientationMode.auto;
    _playerAnimations = true;
    _showTopTime = true;
    _showTopBattery = true;
    _showTopNetSpeed = true;
    _showTopNetType = true;
    _showChapterProgress = true;
    notifyListeners();
  }
}
