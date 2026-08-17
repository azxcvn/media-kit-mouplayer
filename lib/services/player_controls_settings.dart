import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器控制设置：右上角「更多」面板的启用动作、双击手势、快进/快退时长、
/// 常驻进度线、倍速记忆、自定义倍速预设。
///
/// 全局单例（同 [PlaybackProgressService] 模式），ChangeNotifier + shared_preferences
/// 持久化；播放页与「播放器设置」子页共同监听。
class PlayerControlsSettings extends ChangeNotifier {
  static final PlayerControlsSettings instance = PlayerControlsSettings._();

  PlayerControlsSettings._();

  static const _keyTopActions = 'player_controls_top_actions';
  static const _keyDoubleTapMode = 'player_controls_double_tap_mode';
  static const _keyProgressLine = 'player_controls_progress_line';
  static const _keyRememberSpeed = 'player_controls_remember_speed';
  static const _keyLastSpeed = 'player_controls_last_speed';
  static const _keySeek = 'player_controls_seek';
  static const _keyCustomSpeedPresets = 'player_controls_custom_speed_presets';

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

  List<PlayerTopAction> _topActions = const [];
  DoubleTapMode _doubleTapMode = DoubleTapMode.mixed;
  bool _showProgressLine = false;
  bool _rememberSpeed = true;
  double _lastSpeed = 1.0;
  int _seekSeconds = 10;
  List<double> _customSpeedPresets = const [];

  /// 右上角槽位上已放置的动作（有序，最多 [maxTopActions] 个；空列表 = 槽位全空）
  List<PlayerTopAction> get topActions => List.unmodifiable(_topActions);
  DoubleTapMode get doubleTapMode => _doubleTapMode;
  bool get showProgressLine => _showProgressLine;
  bool get rememberSpeed => _rememberSpeed;
  double get lastSpeed => _lastSpeed;
  int get seekSeconds => _seekSeconds;
  List<double> get customSpeedPresets => List.unmodifiable(_customSpeedPresets);

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
    _rememberSpeed = prefs.getBool(_keyRememberSpeed) ?? true;
    _lastSpeed = prefs.getDouble(_keyLastSpeed) ?? 1.0;
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
    notifyListeners();
  }

  Future<void> setDoubleTapMode(DoubleTapMode v) async {
    if (_doubleTapMode == v) return;
    _doubleTapMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDoubleTapMode, v.index);
  }

  Future<void> setShowProgressLine(bool v) async {
    if (_showProgressLine == v) return;
    _showProgressLine = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProgressLine, v);
  }

  Future<void> setRememberSpeed(bool v) async {
    if (_rememberSpeed == v) return;
    _rememberSpeed = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberSpeed, v);
  }

  /// 记录当前倍速（无论是否启用记忆都会保存；启用记忆后下次打开生效）
  Future<void> setSpeed(double v) async {
    _lastSpeed = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLastSpeed, v);
  }

  /// 快进/快退时长（秒），限制在 1 – maxSeekSeconds。双击手势与中央按钮共用。
  Future<void> setSeekSeconds(int v) async {
    final clamped = v.clamp(1, maxSeekSeconds);
    if (_seekSeconds == clamped) return;
    _seekSeconds = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeek, clamped);
  }

  /// 添加自定义倍速预设（去重、限制范围与数量）
  Future<void> addCustomSpeedPreset(double v) async {
    final clamped = v.clamp(minSpeed, maxSpeed);
    if (_customSpeedPresets.any((e) => (e - clamped).abs() < 0.01)) return;
    if (_customSpeedPresets.length >= maxCustomSpeedPresets) return;
    _customSpeedPresets = [..._customSpeedPresets, clamped];
    notifyListeners();
    await _saveCustomSpeedPresets();
  }

  Future<void> removeCustomSpeedPreset(double v) async {
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
    if (_topActions.contains(a) || _topActions.length >= maxTopActions) return;
    _topActions = [..._topActions, a];
    notifyListeners();
    await _saveTopActions();
  }

  Future<void> removeTopAction(PlayerTopAction a) async {
    if (!_topActions.contains(a)) return;
    _topActions = [..._topActions]..remove(a);
    notifyListeners();
    await _saveTopActions();
  }

  /// 槽位排序。配合 ReorderableListView 的 [onReorderItem] 使用：
  /// 该回调已按「移除后插入」修正 newIndex，这里直接 removeAt + insert。
  Future<void> reorderTopAction(int oldIndex, int newIndex) async {
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
    _topActions = const [];
    _doubleTapMode = DoubleTapMode.mixed;
    _showProgressLine = false;
    _rememberSpeed = true;
    _lastSpeed = 1.0;
    _seekSeconds = 10;
    _customSpeedPresets = const [];
    notifyListeners();
  }
}
