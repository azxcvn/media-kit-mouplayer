import 'package:moumou/models/player_loop.dart';

/// 视频播放结束（EOF）后的动作。
///
/// 优先级链参考 kt 项目 `handleEndOfFile()`（fam4k007 小牛播放器）：
/// 单集循环 → 自动连播下一集 → 列表循环回第一集 → 自动退出 → 自动暂停。
enum EndOfFileAction {
  /// 单集循环：seek 0 重播当前视频
  replayCurrent,

  /// 自动连播：播放下一集
  playNext,

  /// 列表循环：回到播放列表第一集
  playFirst,

  /// 自动退出：退出播放页
  exitPlayer,

  /// 自动暂停：seek 到末尾后暂停（停在结尾）
  pauseAtEnd,
}

/// 依据播放设置与播放列表状态解析播放结束后的动作（纯函数，可单测）。
///
/// 判定顺序：
/// 1. [LoopMode.repeatOne] → 重播当前集（最高优先，无视其它设置）；
/// 2. 自动连播开启且存在下一集 → 播放下一集；
/// 3. [LoopMode.loopAll] 且存在播放列表 → 回到第一集（列表循环）；
/// 4. 自动退出开启 → 退出播放页（覆盖「最后一个视频」与「关闭自动连播」
///    等所有无连播路径，与 src 的 `closeAfterEOF` 语义一致）；
/// 5. 兜底 → 自动暂停停在末尾。
EndOfFileAction resolveEndOfFileAction({
  required LoopMode loopMode,
  required bool autoNext,
  required bool autoExit,
  required bool hasPlaylist,
  required bool hasNext,
}) {
  if (loopMode == LoopMode.repeatOne) {
    return EndOfFileAction.replayCurrent;
  }
  if (autoNext && hasNext) {
    return EndOfFileAction.playNext;
  }
  if (loopMode == LoopMode.loopAll && hasPlaylist) {
    return EndOfFileAction.playFirst;
  }
  if (autoExit) {
    return EndOfFileAction.exitPlayer;
  }
  return EndOfFileAction.pauseAtEnd;
}
