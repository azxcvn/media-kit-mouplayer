import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 片头片尾自动跳过设置（工作.md：全局生效，不按文件夹区分）。
///
/// 全局单例（同 [PlayerControlsSettings] 模式），ChangeNotifier +
/// shared_preferences 持久化；「片头片尾」面板与本设置服务共同监听。
///
/// 参考小喵 player 的 SkipSettingsDrawer：
/// - 片头/片尾各维护一对「跳过秒数 + 自定义上限」，滑杆范围 0 – 上限；
/// - 上限可自定义（10 – 600 秒，默认 180），调节滑杆时实时换算分秒；
/// - 一键重置：秒数清零、上限回默认（开关保持不变，对齐 KT 实现）。
class IntroOutroSettings extends ChangeNotifier {
  static final IntroOutroSettings instance = IntroOutroSettings._();

  IntroOutroSettings._();

  /// 加载去重（risk_audit #9）：setter 在改设置前 await [ensureLoaded]，
  /// 防止启动时异步 load 尚未完成、用户已改设置被 load 覆盖（与
  /// [PlayerControlsSettings.ensureLoaded] 同一防护）。
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyEnabled = 'intro_outro_enabled';
  static const _keyIntroSeconds = 'intro_outro_intro_seconds';
  static const _keyIntroRange = 'intro_outro_intro_range';
  static const _keyOutroSeconds = 'intro_outro_outro_seconds';
  static const _keyOutroRange = 'intro_outro_outro_range';

  /// 跳过秒数上限范围（对齐小喵 player 的 MIN_RANGE/MAX_RANGE/DEFAULT_RANGE）
  static const int minRangeSeconds = 10;
  static const int maxRangeSeconds = 600;
  static const int defaultRangeSeconds = 180;

  /// 功能开关（默认关闭；开启后对全部文件生效）
  bool _enabled = false;

  /// 跳过片头秒数（0 = 不跳）
  int _introSeconds = 0;

  /// 片头滑杆上限（10 – 600 秒，默认 180）
  int _introRange = defaultRangeSeconds;

  /// 跳过片尾秒数（0 = 不跳；按剩余时间计算）
  int _outroSeconds = 0;

  /// 片尾滑杆上限（10 – 600 秒，默认 180）
  int _outroRange = defaultRangeSeconds;

  bool get enabled => _enabled;
  int get introSeconds => _introSeconds;
  int get introRange => _introRange;
  int get outroSeconds => _outroSeconds;
  int get outroRange => _outroRange;

  /// 启动时加载（main.dart 调用）
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _introSeconds =
        (prefs.getInt(_keyIntroSeconds) ?? 0).clamp(0, maxRangeSeconds);
    _outroSeconds =
        (prefs.getInt(_keyOutroSeconds) ?? 0).clamp(0, maxRangeSeconds);
    _introRange = (prefs.getInt(_keyIntroRange) ?? defaultRangeSeconds)
        .clamp(minRangeSeconds, maxRangeSeconds);
    _outroRange = (prefs.getInt(_keyOutroRange) ?? defaultRangeSeconds)
        .clamp(minRangeSeconds, maxRangeSeconds);
    // 上限收窄后秒数可能越界，同步收窄
    _introSeconds = _introSeconds.clamp(0, _introRange);
    _outroSeconds = _outroSeconds.clamp(0, _outroRange);
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    await ensureLoaded();
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
  }

  /// 跳过片头秒数（钳制到 0 – [_introRange]）
  Future<void> setIntroSeconds(int v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, _introRange);
    if (_introSeconds == clamped) return;
    _introSeconds = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntroSeconds, clamped);
  }

  /// 片头滑杆上限（10 – 600）；上限收窄时同步收窄跳过秒数
  Future<void> setIntroRange(int v) async {
    await ensureLoaded();
    final clamped = v.clamp(minRangeSeconds, maxRangeSeconds);
    if (_introRange == clamped) return;
    _introRange = clamped;
    if (_introSeconds > clamped) {
      _introSeconds = clamped;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyIntroSeconds, clamped);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntroRange, clamped);
  }

  /// 跳过片尾秒数（钳制到 0 – [_outroRange]）
  Future<void> setOutroSeconds(int v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, _outroRange);
    if (_outroSeconds == clamped) return;
    _outroSeconds = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOutroSeconds, clamped);
  }

  /// 片尾滑杆上限（10 – 600）；上限收窄时同步收窄跳过秒数
  Future<void> setOutroRange(int v) async {
    await ensureLoaded();
    final clamped = v.clamp(minRangeSeconds, maxRangeSeconds);
    if (_outroRange == clamped) return;
    _outroRange = clamped;
    if (_outroSeconds > clamped) {
      _outroSeconds = clamped;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyOutroSeconds, clamped);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOutroRange, clamped);
  }

  /// 一键重置：跳过秒数清零、上限回默认；开关保持不变（对齐 KT 实现）
  Future<void> reset() async {
    await ensureLoaded();
    if (_introSeconds == 0 &&
        _outroSeconds == 0 &&
        _introRange == defaultRangeSeconds &&
        _outroRange == defaultRangeSeconds) {
      return;
    }
    _introSeconds = 0;
    _outroSeconds = 0;
    _introRange = defaultRangeSeconds;
    _outroRange = defaultRangeSeconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntroSeconds, 0);
    await prefs.setInt(_keyOutroSeconds, 0);
    await prefs.setInt(_keyIntroRange, defaultRangeSeconds);
    await prefs.setInt(_keyOutroRange, defaultRangeSeconds);
  }

  /// 测试用：恢复默认值（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void resetForTest() {
    _loadFuture = null; // 下次 setter 重新触发 load（读当前 mock prefs）
    _enabled = false;
    _introSeconds = 0;
    _outroSeconds = 0;
    _introRange = defaultRangeSeconds;
    _outroRange = defaultRangeSeconds;
    notifyListeners();
  }
}
