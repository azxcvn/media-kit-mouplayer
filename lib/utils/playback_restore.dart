import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 播放进度恢复的可靠性工具（横屏/竖屏共用）。
///
/// 背景（历史 bug：重启软件后恢复进度"读到了但跳不过去"）：
/// mpv 只有在时间线激活（播放真正开始）后才接受 seek——冷启动加载窗口内
/// 的 seek 会被**静默丢弃**，且时长上报也可能明显晚于热启动。因此恢复
/// 必须：等时长就绪 → 等播放开始（首个 position>0 事件）→ seek → 用位置流
/// 确认生效（失败重试）。

/// 等待播放真正开始（时间线激活），最多 [timeout]。
///
/// 返回 false 表示超时（播放未能开始，放弃恢复）。
///
/// 工作.md 第 9 点加固：不再以「首个 position > 0」为唯一信号——冷启动 /
/// 快速进出循环时，首个微小 tick 可能出现在 mpv 加载期的临时时间线上，
/// 此时 seek 会被后续加载重置。要求位置推进到 [minStablePosition]
/// （默认 0.5s），说明时间线已稳定激活才返回 true。
Future<bool> waitForPlaybackStart(
  Player player, {
  Duration timeout = const Duration(seconds: 15),
  Duration minStablePosition = const Duration(milliseconds: 500),
}) async {
  if (player.state.position >= minStablePosition) return true;
  final completer = Completer<bool>();
  late final StreamSubscription<Duration> sub;
  sub = player.stream.position.listen((p) {
    if (p >= minStablePosition && !completer.isCompleted) {
      completer.complete(true);
    }
  });
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(false);
  });
  final ok = await completer.future;
  timer.cancel();
  await sub.cancel();
  return ok;
}

/// 等待位置到达 [target] 附近（`>= target - 1s`），用于确认 seek 生效。
///
/// 位置必须 `> 0`（过滤未开始的 0 位置事件），避免目标极小（<1s）时
/// 未 seek 也误判成功。返回 false 表示超时（seek 可能被丢弃）。
Future<bool> waitForPositionReaching(
  Player player,
  Duration target, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final threshold = target - const Duration(seconds: 1);
  final completer = Completer<bool>();
  late final StreamSubscription<Duration> sub;
  sub = player.stream.position.listen((p) {
    if (p > Duration.zero && p >= threshold && !completer.isCompleted) {
      completer.complete(true);
    }
  });
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(false);
  });
  final ok = await completer.future;
  timer.cancel();
  await sub.cancel();
  return ok;
}

/// 是否应恢复播放位置（纯函数，可单测）。
///
/// 阈值规则（v3 用户反馈：循环播放时"无限恢复已看完视频的进度"）：
/// - 时长未知 / 无进度 / 进度 ≥ 时长（已看完）：不恢复；
/// - `saved / duration < [minRestoreRatio]`（默认 5%）：几乎没看，从头播；
/// - `saved / duration >= [maxRestoreRatio]`（默认 90%，调用方可传
///   「已观看进度阈值」设置）：已看完，不恢复（EOF 循环回该视频时
///   若恢复会立即触发下一次 EOF，造成无限跳集）。
bool shouldRestorePosition(
  Duration duration,
  Duration saved, {
  double minRestoreRatio = 0.05,
  double maxRestoreRatio = 0.9,
}) {
  if (duration <= Duration.zero || saved <= Duration.zero) return false;
  if (saved >= duration) return false;
  final ratio = saved.inMilliseconds / duration.inMilliseconds;
  return ratio >= minRestoreRatio && ratio < maxRestoreRatio;
}

/// 完整恢复流程（open 完成后调用）：
/// 1. 等待时长就绪（最多 [durationWaitTimeout]，冷启动初始化可能较慢）；
/// 2. 等待播放稳定开始（时间线激活后 mpv 才接受 seek）；
/// 3. seek 到 [saved] 并用位置流确认，失败重试最多 3 次；
/// 4. **稳定确认**：位置到达目标后再等一小段，复查位置仍在目标附近——
///   若 mpv 加载期把已确认的 seek 重置回开头，则继续重试（工作.md 第 9 点）。
///
/// 阈值判定见 [shouldRestorePosition]（看完/起点不恢复）。
///
/// 返回是否成功恢复（成功才应由调用方显示「已恢复」指示器）。
///
/// 防销毁竞态（risk_audit #2：快速「退出→进入」循环刷假崩溃日志）：
/// - [isCancelled]：调用方（播放页）在 dispose 时置位，本函数在每次
///   重试前检查，一旦取消立即静默返回 false；
/// - 整体包 try/catch：播放器被销毁后 `player.seek` / 流订阅会抛
///   `AssertionError: [Player] has been disposed`（media_kit 无论 debug/
///   release 都抛），捕获后静默返回 false，不再被全局兜底写入崩溃日志。
Future<bool> restorePlaybackPosition(
  Player player,
  Duration saved, {
  double minRestoreRatio = 0.05,
  double maxRestoreRatio = 0.9,
  Duration durationWaitTimeout = const Duration(seconds: 15),
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() ?? false) return false;
  try {
    // 1) 等时长就绪
    final deadline = DateTime.now().add(durationWaitTimeout);
    while (player.state.duration <= Duration.zero &&
        DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) return false;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final duration = player.state.duration;
    if (!shouldRestorePosition(
      duration,
      saved,
      minRestoreRatio: minRestoreRatio,
      maxRestoreRatio: maxRestoreRatio,
    )) {
      return false;
    }
    // 2) 等播放稳定开始
    if (!await waitForPlaybackStart(player)) return false;
    // 3) seek + 确认 + 稳定复查（重试最多 3 次）
    const settle = Duration(milliseconds: 600);
    const tolerance = Duration(seconds: 2);
    for (var i = 0; i < 3; i++) {
      if (isCancelled?.call() ?? false) return false;
      await player.seek(saved);
      if (!await waitForPositionReaching(player, saved)) continue;
      // 4) 稳定确认：seek 生效后等一小段，确认位置仍停留在目标附近
      //（mpv 加载期可能把确认过的位置重置回开头 → 回到 3 重试）
      await Future.delayed(settle);
      final p = player.state.position;
      if (p > Duration.zero && p >= saved - tolerance) {
        return true;
      }
    }
    return false;
  } on AssertionError {
    // 播放器已被销毁（快速退出→进入循环）：静默返回，不污染崩溃日志
    return false;
  }
}
