/// 片头片尾自动跳过的动作决策纯函数（参考小喵 player 的
/// SkipIntroOutroManager.handleSkipIntroOutro 手动时间跳过模式）。
library;

/// 片头片尾自动跳过动作
enum IntroOutroAction {
  /// 不动作
  none,

  /// 跳过片头：seek 到片头结束（片头跳过秒数）
  skipIntro,

  /// 跳过片尾：跳到下一集（无下一集时不产生此动作）
  nextEpisode,
}

/// 评估当前播放位置是否触发片头/片尾自动跳过。
///
/// 规则：
/// - 片头：位置仍在片头范围内（`positionSeconds < introSeconds`）且片头
///   未处理（[introHandled]）→ 跳过片头；片头长度必须小于视频总长
///   （否则整集都是片头，跳完即 EOF 会误连播，故不跳）；
/// - 片尾：剩余时长 ≤ `outroSeconds` 且片尾未处理（[outroHandled]）且
///   存在下一集（[hasNext]）→ 跳到下一集；片尾长度必须小于视频总长；
/// - 每集片头/片尾各触发一次，由跟踪器（[introHandled]/[outroHandled]）
///   维护状态；
/// - 片头优先于片尾（同位置同时命中时先跳片头）。
IntroOutroAction resolveIntroOutroAction({
  required bool enabled,
  required int introSeconds,
  required int outroSeconds,
  required double positionSeconds,
  required double durationSeconds,
  required bool introHandled,
  required bool outroHandled,
  required bool hasNext,
}) {
  if (!enabled) return IntroOutroAction.none;
  if (durationSeconds <= 0) return IntroOutroAction.none;
  if (introSeconds > 0 && !introHandled) {
    if (positionSeconds < introSeconds && introSeconds < durationSeconds) {
      return IntroOutroAction.skipIntro;
    }
  }
  if (outroSeconds > 0 && !outroHandled && hasNext) {
    if (outroSeconds < durationSeconds &&
        positionSeconds >= durationSeconds - outroSeconds) {
      return IntroOutroAction.nextEpisode;
    }
  }
  return IntroOutroAction.none;
}
