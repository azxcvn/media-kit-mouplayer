/// 通用格式化工具：文件大小 / 日期 / 时长（文件夹卡片与视频卡片共用）
library;

/// 字节数 → 人类可读大小（B / KB / MB / GB）
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// 日期 → yyyy-MM-dd（null 返回空串）
String formatDate(DateTime? dt) {
  if (dt == null) return '';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// 毫秒 → 时长文本（mm:ss 或 h:mm:ss）
String formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 倍速显示：1.0 → '1.0x'，1.25 → '1.25x'（播放器倍速胶囊 / 倍速面板共用）
String formatSpeed(double speed) {
  final s = speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2);
  return '${s}x';
}

/// 网速显示（工作.md 阶段1 第 1 点）：自动切换 KB/MB，保留两位小数。
/// [bytesPerSecond] 为每秒字节数：< 1024 KB/s 显示 KB，否则显示 MB。
String formatNetworkSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0.00 KB/s';
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(2)} KB/s';
  return '${(kb / 1024).toStringAsFixed(2)} MB/s';
}

/// 判断媒体路径是否为在线资源（工作.md 阶段1 第 1 点：网速详情仅在线播放时显示）。
/// 本地文件返回 false，http/https/rtmp/rtsp 等网络协议返回 true。
bool isOnlineMedia(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('rtmp://') ||
      lower.startsWith('rtsp://') ||
      lower.startsWith('mms://') ||
      lower.startsWith('srt://');
}
