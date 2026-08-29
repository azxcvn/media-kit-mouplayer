import 'package:flutter/foundation.dart';

/// 音频均衡器预设（工作.md 均衡器功能）。
///
/// 每个预设只描述 5 段增益（dB），低音增强与虚拟环绕是独立滑块，不属于预设。
/// 5 段中心频率与小喵 player 一致：60Hz / 230Hz / 910Hz / 3.6kHz / 14kHz。
///
/// 预设面向**视频 / 影视观看**而非音乐播放（音乐型「摇滚 V 形 / 爵士温暖」等
/// 是针对已混音成品做的微调，幅度保守；看视频更关心对白清晰度、低频冲击、
/// 高频细节与夜间不扰民，且源声往往未精细混音，需要更果断的 ±6~8dB 增益）。
/// 取值参考电视机 / AVR / Kodi / VLC 常见的影视 EQ 档位：
/// - 平直：旁路（默认）；
/// - 对白增强：抬 1k~4k 人声清晰带、压低频轰鸣；
/// - 电影：V 形（深低音 + 空气感高音 + 轻微中频凹陷，营造纵深）；
/// - 低音震撼：抬 60/230Hz，动作 / 爆炸冲击；
/// - 高音清晰：抬 3.6k/14k，细节与环境声；
/// - 柔和夜间：压低音轰鸣与刺耳高频、保对白，深夜观影不扰邻。
@immutable
class EqualizerPreset {
  /// 稳定标识（持久化用）
  final String id;

  /// 展示名（中文）
  final String label;

  /// 5 段增益（dB），范围 -15 ~ +15，长度恒为 5
  final List<double> bands;

  const EqualizerPreset(this.id, this.label, this.bands);
}

/// 5 段中心频率展示标签（与小喵 player 一致）
const List<String> kEqualizerBandLabels = [
  '60Hz',
  '230Hz',
  '910Hz',
  '3.6kHz',
  '14kHz',
];

/// 频段数（固定 5 段）
const int kEqualizerBandCount = 5;

/// 单段增益范围（dB，步进 1）
const double kEqualizerMinBandDb = -15;
const double kEqualizerMaxBandDb = 15;

/// 内置影视向预设列表（含「平直」作为默认/旁路基线）。
///
/// 增益为相对 0dB 的幅度，关键频段用 ±6~8dB 以保证可闻、不刺耳。
const List<EqualizerPreset> kEqualizerPresets = [
  EqualizerPreset('flat', '平直', [0, 0, 0, 0, 0]),
  EqualizerPreset('dialogue', '对白增强', [-3, -1, 3, 6, 4]),
  EqualizerPreset('cinema', '电影', [6, 3, -1, 3, 6]),
  EqualizerPreset('bass', '低音震撼', [8, 4, 0, 0, 0]),
  EqualizerPreset('treble', '高音清晰', [0, 0, 2, 5, 7]),
  EqualizerPreset('night', '柔和夜间', [-6, -3, 2, 3, -5]),
];

/// 按 id 反查预设，找不到返回 null（如旧数据指向已删除的预设）。
EqualizerPreset? equalizerPresetById(String? id) {
  if (id == null) return null;
  for (final p in kEqualizerPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 判断两组 5 段增益是否逐段相等（容差 0.01 dB，纯函数，可单测）。
bool equalizerBandsEqual(List<double> a, List<double> b) {
  if (a.length != kEqualizerBandCount || b.length != kEqualizerBandCount) {
    return false;
  }
  for (var i = 0; i < kEqualizerBandCount; i++) {
    if ((a[i] - b[i]).abs() > 0.01) return false;
  }
  return true;
}
