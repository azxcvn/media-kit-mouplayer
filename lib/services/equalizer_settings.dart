import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:moumou/models/equalizer_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频均衡器设置（工作.md 均衡器功能）：全局持久化的均衡器状态。
///
/// 与小喵 player 的 `PreferencesManager`（EQ_ENABLED / EQ_BAND_0..4 /
/// EQ_BASS_BOOST / EQ_VIRTUALIZER）对齐，额外增加「当前预设 id」以在 UI
/// 高亮选中的预设。全局单例（同 [SubtitleSettings] 模式）：
/// ChangeNotifier + shared_preferences 持久化，播放页均衡器面板与
/// [AudioController] 共同监听。
///
/// 与小喵 player 一致，均衡器是**跨会话持久化**状态（区别于声道/音频处理
/// 的会话级状态）；用户调节后立即写盘并重应用 mpv `af` 滤镜链。
class EqualizerSettings extends ChangeNotifier {
  static final EqualizerSettings instance = EqualizerSettings._();

  EqualizerSettings._();

  /// 加载去重（同 PlayerControlsSettings.ensureLoaded）
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyEnabled = 'eq_enabled';
  static const _keyBandPrefix = 'eq_band_'; // eq_band_0 ~ eq_band_4
  static const _keyBassBoost = 'eq_bass_boost';
  static const _keyVirtualizer = 'eq_virtualizer';
  static const _keyPreset = 'eq_preset';

  /// 低音增强 / 虚拟环绕范围（0-100，百分比）
  static const double minBoost = 0;
  static const double maxBoost = 100;

  bool _enabled = false;
  final List<double> _bands = List.filled(kEqualizerBandCount, 0);
  int _bassBoost = 0;
  int _virtualizer = 0;
  String? _presetId;

  bool get enabled => _enabled;
  List<double> get bands => List.unmodifiable(_bands);
  int get bassBoost => _bassBoost;
  int get virtualizer => _virtualizer;

  /// 当前命中的预设 id（null = 手动自定义，不与任何预设完全一致）
  String? get presetId => _presetId;

  /// 5 段是否全为 0（纯平直，UI 与 af 链构建都会用到）
  bool get isFlat => _bands.every((b) => b.abs() < 0.01);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    for (var i = 0; i < kEqualizerBandCount; i++) {
      _bands[i] = (prefs.getDouble('$_keyBandPrefix$i') ?? 0)
          .clamp(kEqualizerMinBandDb, kEqualizerMaxBandDb)
          .toDouble();
    }
    _bassBoost =
        (prefs.getInt(_keyBassBoost) ?? 0).round().clamp(0, 100).toInt();
    _virtualizer =
        (prefs.getInt(_keyVirtualizer) ?? 0).round().clamp(0, 100).toInt();
    final presetRaw = prefs.getString(_keyPreset);
    // 预设 id 只保留仍在内置列表中的；旧数据指向已删除预设时回退 null
    _presetId = equalizerPresetById(presetRaw)?.id;
    notifyListeners();
  }

  /// 开 / 关均衡器（关不丢各段与低音/虚拟值，重开即恢复）。
  Future<void> setEnabled(bool v) async {
    await ensureLoaded();
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
  }

  /// 设置某段增益（dB，-15 ~ +15，取整到 1dB）。
  /// 手动改段视为「自定义」，清空预设高亮。
  Future<void> setBand(int index, double v) async {
    await ensureLoaded();
    if (index < 0 || index >= kEqualizerBandCount) return;
    final clamped = v
        .roundToDouble()
        .clamp(kEqualizerMinBandDb, kEqualizerMaxBandDb)
        .toDouble();
    if ((_bands[index] - clamped).abs() < 0.01) return;
    _bands[index] = clamped;
    _presetId = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_keyBandPrefix$index', clamped);
    await prefs.remove(_keyPreset);
  }

  /// 应用一个预设：覆盖 5 段增益 + 记录预设 id。
  Future<void> applyPreset(EqualizerPreset preset) async {
    await ensureLoaded();
    var changed = false;
    for (var i = 0; i < kEqualizerBandCount; i++) {
      final b = preset.bands[i]
          .roundToDouble()
          .clamp(kEqualizerMinBandDb, kEqualizerMaxBandDb)
          .toDouble();
      if ((_bands[i] - b).abs() >= 0.01) {
        _bands[i] = b;
        changed = true;
      }
    }
    if (!changed && _presetId == preset.id) return;
    _presetId = preset.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < kEqualizerBandCount; i++) {
      await prefs.setDouble('$_keyBandPrefix$i', _bands[i]);
    }
    await prefs.setString(_keyPreset, preset.id);
  }

  /// 设置低音增强强度（0-100，取整）。
  Future<void> setBassBoost(int v) async {
    await ensureLoaded();
    final clamped = v.round().clamp(0, 100).toInt();
    if (_bassBoost == clamped) return;
    _bassBoost = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBassBoost, clamped);
  }

  /// 设置虚拟环绕强度（0-100，取整）。
  Future<void> setVirtualizer(int v) async {
    await ensureLoaded();
    final clamped = v.round().clamp(0, 100).toInt();
    if (_virtualizer == clamped) return;
    _virtualizer = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVirtualizer, clamped);
  }

  /// 一键重置：关、全平、低音/虚拟归零、清空预设高亮（保留开关状态语义：
  /// 与小喵 player 一致，重置后开关保持原状，仅归零各项数值）。
  Future<void> resetValues() async {
    await ensureLoaded();
    var changed = false;
    for (var i = 0; i < kEqualizerBandCount; i++) {
      if (_bands[i].abs() >= 0.01) {
        _bands[i] = 0;
        changed = true;
      }
    }
    if (_bassBoost != 0) {
      _bassBoost = 0;
      changed = true;
    }
    if (_virtualizer != 0) {
      _virtualizer = 0;
      changed = true;
    }
    if (_presetId != null) {
      _presetId = null;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < kEqualizerBandCount; i++) {
      await prefs.setDouble('$_keyBandPrefix$i', 0);
    }
    await prefs.setInt(_keyBassBoost, 0);
    await prefs.setInt(_keyVirtualizer, 0);
    await prefs.remove(_keyPreset);
  }

  /// 测试用：恢复默认值（单例在测试间共享，避免状态泄漏）。
  @visibleForTesting
  void reset() {
    _loadFuture = null;
    _enabled = false;
    for (var i = 0; i < kEqualizerBandCount; i++) {
      _bands[i] = 0;
    }
    _bassBoost = 0;
    _virtualizer = 0;
    _presetId = null;
    notifyListeners();
  }

  /// 序列化当前值（诊断 / 日志用，非持久化路径）。
  @override
  String toString() =>
      'EqualizerSettings(enabled: $_enabled, bands: ${jsonEncode(_bands)}, '
      'bassBoost: $_bassBoost, virtualizer: $_virtualizer, preset: $_presetId)';
}
