import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 解码方式档位（对齐 mpvRx / 小喵生态「自动 / 硬解 / 硬解+ / 软解」习惯）。
///
/// [hwdec] 为 mpv 的 `--hwdec` 值；「硬解+」为直通优先的有序回退链
/// （`mediacodec` 在 `vo=gpu` 下会初始化失败，自动落到 `mediacodec-copy`）。
enum DecodeMode {
  autoSafe('自动', 'auto-safe', '自动选择安全硬解'),
  hwCopy('硬解', 'mediacodec-copy', '强制硬解，兼容字幕与超分'),
  hwPlus('硬解+', 'mediacodec,mediacodec-copy,no', '直通优先，失败自动回退'),
  sw('软解', 'no', '纯 CPU 解码');

  final String label;
  final String hwdec;
  final String description;

  const DecodeMode(this.label, this.hwdec, this.description);
}

/// 解码性能预设（对齐 mpvRx / 小喵生态的 MPV Profile 六档）。
///
/// [profile] 为 **mpv 内置 profile 名**（编译在 libmpv.so 里，与 mpvRx 的
/// `setOptionString("profile", ...)` 完全一致）；应用时写入 mpv 的 `profile`
/// 属性（重启播放器后生效）。「default」在 mpv 内置 profile 中不存在，设为
/// 空串表示不应用任何 profile（回到 mpv 默认行为）。
enum DecodePreset {
  fast('快速', '性能优先', 'fast'),
  standard('默认', '标准配置', ''),
  highQuality('高质量', '画质优先', 'high-quality'),
  gpuHq('GPU 高质量', '高画质渲染', 'gpu-hq'),
  lowLatency('低延迟', '减少缓冲', 'low-latency'),
  swFast('软解快速', '软解加速', 'sw-fast');

  final String label;
  final String description;
  final String profile;

  const DecodePreset(this.label, this.description, this.profile);
}

/// 解码设置：全局单例，ChangeNotifier + shared_preferences 持久化。
///
/// 播放页创建 [VideoController] 时读取 [mode] 注入 `hwdec`/`vo`，并在初始化后
/// 写入 [preset] 的 `profile` 属性；两者均**重启播放器（重开视频）后生效**。
class DecodeSettings extends ChangeNotifier {
  static final DecodeSettings instance = DecodeSettings._();

  DecodeSettings._();

  /// 加载去重：setter 在改设置前 await [ensureLoaded]，防启动加载未完成时
  /// 用户已改设置被 load 覆盖（同 PlayerControlsSettings 的 risk_audit #9 防护）。
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyMode = 'decode_mode';
  static const _keyPreset = 'decode_preset';

  DecodeMode _mode = DecodeMode.autoSafe;

  /// 当前解码档位（默认自动）
  DecodeMode get mode => _mode;

  DecodePreset _preset = DecodePreset.fast;

  /// 当前解码预设（默认快速）
  DecodePreset get preset => _preset;

  /// 从磁盘加载
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyMode);
    if (raw != null) {
      for (final m in DecodeMode.values) {
        if (m.hwdec == raw) {
          _mode = m;
          break;
        }
      }
    }
    final presetRaw = prefs.getString(_keyPreset);
    if (presetRaw != null) {
      for (final p in DecodePreset.values) {
        if (p.name == presetRaw) {
          _preset = p;
          break;
        }
      }
    }
    notifyListeners();
  }

  /// 切换解码档位并持久化
  Future<void> setMode(DecodeMode v) async {
    await ensureLoaded();
    if (_mode == v) return;
    _mode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, v.hwdec);
  }

  /// 切换解码预设并持久化
  Future<void> setPreset(DecodePreset v) async {
    await ensureLoaded();
    if (_preset == v) return;
    _preset = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, v.name);
  }
}
