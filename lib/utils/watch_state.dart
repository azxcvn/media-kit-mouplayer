/// 视频观看状态：未观看 / 观看中 / 已看完
enum WatchState { notWatched, watching, watched }

/// 根据播放进度与「已观看」阈值判定观看状态（纯函数，可单测）。
///
/// - 无进度或时长为 0 → 未观看；
/// - 进度 > 0 且 < 阈值 → 观看中；
/// - 进度 >= 阈值 → 已看完。
WatchState classifyWatchState({
  required int durationMs,
  required Duration? progress,
  required double threshold,
}) {
  if (durationMs <= 0 || progress == null) return WatchState.notWatched;
  final ratio = progress.inMilliseconds / durationMs;
  if (ratio <= 0) return WatchState.notWatched;
  if (ratio >= threshold) return WatchState.watched;
  return WatchState.watching;
}

/// 观看进度百分比（0 – 100，整数），无进度/无时长返回 0
int watchPercent({required int durationMs, required Duration? progress}) {
  if (durationMs <= 0 || progress == null) return 0;
  final ratio = progress.inMilliseconds / durationMs;
  if (ratio <= 0) return 0;
  return (ratio * 100).round().clamp(0, 100);
}
