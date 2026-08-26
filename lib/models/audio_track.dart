import 'package:flutter/foundation.dart';

/// 音频轨道（工作.md 音频功能）：播放器当前媒体可用的音频轨道。
///
/// 数据来自 mpv `track-list` 子属性（内嵌音轨）或 `audio-add` 添加的外部音轨；
/// [external] 为 true 表示外部音轨（临时，退出播放/切集后不保留）。
@immutable
class AudioTrack {
  /// mpv 轨道 id（`track-list/$i/id`，字符串形式）
  final String id;

  /// 轨道标题（`title` 属性，可能为空）
  final String? title;

  /// 语言代码（`lang` 属性，可能为空）
  final String? language;

  /// 是否为外部音轨（通过 `audio-add` 添加；临时，切集/退出后消失）
  final bool external;

  /// 音频编码格式（`codec` 属性：aac / flac / opus 等，可能为空）
  final String? codec;

  /// 声道布局（`demux-channels` 属性：stereo / 5.1 等，可能为空）
  final String? channels;

  /// 音轨源路径（mpv `external-filename`，外部音轨为文件绝对路径；内嵌为 null）。
  final String? sourcePath;

  const AudioTrack({
    required this.id,
    this.title,
    this.language,
    this.external = false,
    this.codec,
    this.channels,
    this.sourcePath,
  });

  /// 展示名：优先标题，其次语言，最后回退「音轨 N」
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    if (language != null && language!.trim().isNotEmpty) return language!.trim();
    return '音轨 $id';
  }
}

/// 音频声道（工作.md 音频功能）：对齐 mpvRx 的 `AudioChannels`。
///
/// [auto]/[autoSafe]/[mono]/[stereo] 直接映射 mpv `audio-channels` 属性；
/// [reverseStereo]（反向立体声）通过 `af` 滤镜 `pan=[stereo|c0=c1|c1=c0]`
/// 交换左右声道实现，此时 `audio-channels` 需先重置为 `auto-safe`（见
/// [audioChannelsPropertyValue]）。
enum AudioChannels {
  auto('自动', 'audio-channels', 'auto'),
  autoSafe('安全自动', 'audio-channels', 'auto-safe'),
  mono('单声道', 'audio-channels', 'mono'),
  stereo('立体声', 'audio-channels', 'stereo'),
  reverseStereo('反向立体声', 'af', 'pan=[stereo|c0=c1|c1=c0]');

  final String label;
  final String property;
  final String value;
  const AudioChannels(this.label, this.property, this.value);

  /// 按持久化标识（枚举 name）反查，找不到返回 [autoSafe]。
  static AudioChannels byName(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return AudioChannels.autoSafe;
  }
}

/// 支持的外部音轨扩展名（对齐 mpvRx `FileTypeUtils.AUDIO_EXTENSIONS`）。
const Set<String> kSupportedAudioExtensions = {
  'mp3', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav', 'wave',
  'wma', 'ac3', 'eac3', 'dts', 'ape', 'mka', 'aif', 'aiff', 'aifc',
  'mpc', 'tta', 'tak', 'caf', 'au', 'snd', 'ra', 'weba', '3ga',
  'dsf', 'dff', 'mlp', 'truehd', 'mid', 'midi', 'mp1', 'mp2', 'mpa',
  'spx', 'amr', 'awb',
};

/// 判断文件名是否为支持的音轨格式（纯函数，可单测；大小写不敏感）。
bool isSupportedAudioFile(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  final ext = filename.substring(dot + 1).toLowerCase();
  return kSupportedAudioExtensions.contains(ext);
}

/// 音轨在面板中的展示名（纯函数，可单测）。
/// 返回 `displayTitle` + 外挂标记 + 格式后缀，如「国语 · 外挂 · aac」。
String audioTrackLabel(AudioTrack track) {
  final parts = <String>[track.displayTitle];
  if (track.external) parts.add('外挂');
  if (track.codec != null && track.codec!.trim().isNotEmpty) {
    parts.add(track.codec!.trim());
  }
  return parts.join(' · ');
}

/// 计算 `audio-channels` 属性实际写入值（纯函数，可单测）。
///
/// 反向立体声不改声道布局，而是用 `af` 滤镜交换左右声道，故先把布局
/// 重置为 `auto-safe`（mpvRx 同款：AudioTracksSheet 里选 ReverseStereo 时
/// setProperty(AutoSafe.property, AutoSafe.value)）。
String audioChannelsPropertyValue(AudioChannels channels) {
  if (channels == AudioChannels.reverseStereo) return AudioChannels.autoSafe.value;
  return channels.value;
}

/// 组装 mpv `af` 音频滤镜链（纯函数，可单测；对齐 mpvRx
/// `PlayerViewModel.updateMpvAfProperty` 的 DRC / 音量标准化 / 反向立体声）：
///
/// - 动态范围压缩 → `lavfi=[acompressor=threshold=-20dB:ratio=4:attack=5:release=50:makeup=2]`
/// - 音量标准化 → `dynaudnorm`
/// - 反向立体声 → `pan=[stereo|c0=c1|c1=c0]`
///
/// 返回逗号拼接串；无滤镜时返回空串（`af` 置空即清除滤镜链）。
String buildAudioFilterChain({
  required AudioChannels channels,
  required bool volumeNormalization,
  required bool drc,
}) {
  final parts = <String>[];
  if (drc) {
    parts.add(
      'lavfi=[acompressor=threshold=-20dB:ratio=4:attack=5:release=50:makeup=2]',
    );
  }
  if (volumeNormalization) {
    parts.add('dynaudnorm');
  }
  if (channels == AudioChannels.reverseStereo) {
    parts.add('pan=[stereo|c0=c1|c1=c0]');
  }
  return parts.join(',');
}
