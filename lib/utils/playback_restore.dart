import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 播放进度恢复的可靠性工具（横屏/竖屏共用）。
///
/// 背景（历史 bug：重启软件后恢复进度"读到了但跳不过去"）：
/// mpv 只有在时间线激活（播放真正开始）后才接受 seek——冷启动加载窗口内
/// 的 seek 会被**静默丢弃**，且时长上报也可能明显晚于热启动。因此恢复
/// 必须：等时长就绪 → 等播放开始（首个 position>0 事件）→ seek → 用位置流
/// 确认生效（失败重试）。

/// 等待播放真正开始（首个 `position > 0` 事件），最多 [timeout]。
///
/// 返回 false 表示超时（播放未能开始，放弃恢复）。
Future<bool> waitForPlaybackStart(
  Player player, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (player.state.position > Duration.zero) return true;
  final completer = Completer<bool>();
  late final StreamSubscription<Duration> sub;
  sub = player.stream.position.listen((p) {
    if (p > Duration.zero && !completer.isCompleted) {
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
/// 2. 等待播放真正开始（时间线激活后 mpv 才接受 seek）；
/// 3. seek 到 [saved] 并用位置流确认，失败重试最多 3 次。
///
/// 阈值判定见 [shouldRestorePosition]（看完/起点不恢复）。
///
/// 返回是否成功恢复（成功才应由调用方显示「已恢复」指示器）。
Future<bool> restorePlaybackPosition(
  Player player,
  Duration saved, {
  double minRestoreRatio = 0.05,
  double maxRestoreRatio = 0.9,
  Duration durationWaitTimeout = const Duration(seconds: 15),
}) async {
  // 1) 等时长就绪
  final deadline = DateTime.now().add(durationWaitTimeout);
  while (player.state.duration <= Duration.zero &&
      DateTime.now().isBefore(deadline)) {
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
  // 2) 等播放开始
  if (!await waitForPlaybackStart(player)) return false;
  // 3) seek + 确认（重试最多 3 次）
  for (var i = 0; i < 3; i++) {
    await player.seek(saved);
    if (await waitForPositionReaching(player, saved)) return true;
  }
  return false;
}
