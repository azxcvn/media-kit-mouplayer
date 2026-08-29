/// 弹幕时间轴纯函数（同秒多条错峰发射，对齐 Kazumi `DanmakuTimeline`）。
library;

/// 同一秒桶内的多条弹幕在 1 秒内错峰发射的延迟（毫秒）。
///
/// [index] / [total] 为该批弹幕在本次发射中的序号与总数；
/// 例如 4 条同秒弹幕的延迟分别为 0 / 250 / 500 / 750 毫秒，
/// 避免同一秒的全部弹幕在同一瞬间扎堆上屏。
int staggerDelayMilliseconds({required int index, required int total}) {
  if (total <= 0) return 0;
  return index * 1000 ~/ total;
}
