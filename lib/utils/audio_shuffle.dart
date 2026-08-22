/// 听视频界面的随机播放算法（工作.md 第 10 点）。
///
/// 设计思路（大胆发散）：真正的「随机」应该结合**用户当前的时间刻**——
/// 把当前时刻（时/分/秒/毫秒）折叠成一个整数种子，经确定性散列后映射到
/// 播放列表索引。这样：
/// - 每次切歌都基于「当下这一刻」计算，结果不可预测但可复现（同一时刻
///   计算结果一致），更像「命运轮盘」而不是简单洗牌；
/// - 不需要维护洗牌后的索引表，切回/重进也无需恢复状态；
/// - 保证不会与当前曲目重复（听众不会连续听到同一首）。
///
/// 纯函数，可单测（见 test/audio_shuffle_test.dart）。
library;

/// 计算听视频模式下「下一曲」在播放列表中的索引。
///
/// [listLength] 播放列表长度（≥1）；[currentIndex] 当前曲目索引；
/// [now] 当前时刻（随机种子来源）。
///
/// - 列表只有 1 个时恒返回 0；
/// - 返回索引 ∈ [0, listLength)，且 != [currentIndex]（listLength ≥ 2 时）；
/// - 同一毫秒内结果确定；不同时刻结果通常不同。
int audioShuffleNextIndex({
  required int listLength,
  required int currentIndex,
  required DateTime now,
}) {
  if (listLength <= 1) return 0;
  // 1) 把当前时间刻折叠成整数种子：时分秒毫秒 → 单个整数。
  //    用「当天已流逝的毫秒数」而非时间戳，保证结果与日期无关（只与时刻有关），
  //    用户每天同一时刻听歌会得到一致的"命运"，可复现、可解释。
  final msOfDay =
      ((now.hour * 60 + now.minute) * 60 + now.second) * 1000 + now.millisecond;
  // 2) 确定性散列（混合 32 位）：乘性散列 + 异或折叠，打散低位分布。
  var h = msOfDay;
  h = (h * 2654435761) & 0x7FFFFFFF; // Knuth 乘性散列
  h ^= (h >> 13);
  h = (h * 0x45D9F3B) & 0x7FFFFFFF;
  h ^= (h >> 16);
  // 3) 映射到 [0, listLength)，并保证不与当前曲目重复：
  //    取 h 对 listLength 的余数；若恰好等于当前索引，就顺移一格（环形）。
  var next = h % listLength;
  if (next == currentIndex) {
    next = (next + 1) % listLength;
  }
  return next;
}
