/// 弹幕调度器（纯逻辑，无 Flutter / media_kit 依赖，可单测）：
/// 秒桶索引 + 1s tick 前向补发 + seek 跳变检测 + 代数失效。
///
/// 模型对齐 Kazumi 现网方案（秒桶 + 1s Timer + stagger + generation），
/// 并做一处增强：tick 间**前向补发** `(上一秒, 当前秒]` 的全部桶——
/// 高倍速（一 tick 跨多秒）与计时抖动下不丢弹幕（Kazumi 只发当前桶，
/// 1x 下 tick 抖动跨秒也会丢桶）。
library;

import 'package:moumou/models/danmaku_entry.dart';

/// 一次 1s tick 的发射决策结果。
class DanmakuTickResult {
  /// 本 tick 需要发射的弹幕（按时间升序，供 stagger 错峰）
  final List<DanmakuEntry> entries;

  /// 是否检测到 seek 跳变（调用方需清屏；本 tick 不发射）
  final bool seeked;

  const DanmakuTickResult(this.entries, this.seeked);
}

class DanmakuScheduler {
  /// seek 判定阈值（毫秒）：tick 间位移超出「倍速期望 + 阈值」或反向
  /// 超过阈值视为 seek（清屏防旧弹幕残留）；阈值内的微幅回抖不重发。
  static const int _seekThresholdMs = 2000;

  /// 实时 seek 检测（位置流事件）的反向跳变阈值：正常播放事件间位移
  /// 不会倒退超过 1 秒。
  static const int seekBackwardThresholdMs = 1000;

  /// 实时 seek 检测（位置流事件）的正向松弛量：实际位移超出
  /// 「倍速 × 事件间隔 + 松弛量」判为 seek；松弛量吸收事件投递抖动。
  static const int seekForwardSlackMs = 1000;

  /// 位置流跳变判定（纯函数，实时 seek 检测用）。
  ///
  /// 以「当前倍速 × 两次事件间的实际流逝时间」为期望位移：实际位移
  /// 反向超过 [seekBackwardThresholdMs]，或正向超出期望 +
  /// [seekForwardSlackMs]，判为 seek（调用方清屏 + 锚点对齐）。
  /// 卡顿/缓冲导致事件迟到时墙钟间隔同步变大，不会误判。
  static bool isSeekJump({
    required Duration previousPosition,
    required Duration currentPosition,
    required int elapsedMs,
    required double rate,
  }) {
    final actualMs =
        currentPosition.inMilliseconds - previousPosition.inMilliseconds;
    if (actualMs < -seekBackwardThresholdMs) return true;
    final expectedMs = (rate * elapsedMs).round();
    return actualMs > expectedMs + seekForwardSlackMs;
  }

  final Map<int, List<DanmakuEntry>> _buckets = {};

  /// 代数：reset/invalidate/seek 时自增，使在途的延迟发射回调作废
  int _generation = 0;

  /// 上次 tick 发射到的秒桶（null = 重置后尚未锚定）
  int? _lastEmittedSecond;

  /// 上次 tick 的位置（seek 检测用）
  Duration? _lastTickPosition;

  int get generation => _generation;

  /// 是否已装载弹幕数据
  bool get hasDanmaku => _buckets.isNotEmpty;

  /// 装载的弹幕总条数
  int get danmakuCount {
    var count = 0;
    for (final list in _buckets.values) {
      count += list.length;
    }
    return count;
  }

  /// 重置：清空秒桶 + 代数失效 + 位置基准重置（切集 / 重新加载）。
  void reset() {
    _buckets.clear();
    _generation++;
    _lastEmittedSecond = null;
    _lastTickPosition = null;
  }

  /// 仅代数失效（清空在途延迟回调），保留秒桶（开关弹幕等清屏场景）。
  void invalidate() => _generation++;

  /// 实时 seek 通知（位置流检测到跳变时调用，先于 1s tick）：
  /// 代数失效（在途延迟回调立即作废）+ 秒桶锚点/位置基准对齐到跳变后
  /// 的位置——下一个 tick 补发落点秒起的弹幕（锚点取落点秒 - 1，
  /// 与 Kazumi「清屏后等新弹幕」一致，落点秒内容不丢）。
  void notifySeeked(Duration position) {
    _generation++;
    _lastEmittedSecond = position.inSeconds - 1;
    _lastTickPosition = position;
  }

  /// 装载弹幕（按秒分桶；可多次调用追加）。
  void feed(List<DanmakuEntry> entries) {
    for (final entry in entries) {
      (_buckets[entry.timeSeconds] ??= <DanmakuEntry>[]).add(entry);
    }
  }

  /// 一次 1s tick 的发射决策。
  ///
  /// - [position]：当前播放位置；[rate]：当前倍速（期望位移 = rate × 1s）；
  /// - 重置后首个 tick：只发当前桶并锚定（恢复进度到中途不倾倒历史弹幕）；
  /// - 位移跳变（正反向超出阈值）：视为 seek，代数失效 + 返回 `seeked`
  ///   （调用方清屏，本 tick 不发射）；
  /// - 其余：发射 `(上一秒, 当前秒]` 的全部桶（前向补发），秒桶锚点只进不退。
  DanmakuTickResult onTick(Duration position, double rate) {
    final second = position.inSeconds;
    final last = _lastEmittedSecond;
    final lastPosition = _lastTickPosition;
    _lastTickPosition = position;

    if (last == null || lastPosition == null) {
      // 重置后首个 tick：只发当前桶（Kazumi 语义），锚定秒桶
      _lastEmittedSecond = second;
      return DanmakuTickResult(_buckets[second] ?? const [], false);
    }

    final deltaMs = position.inMilliseconds - lastPosition.inMilliseconds;
    final expectedMs = (rate * 1000).round();
    final seeked = deltaMs > expectedMs + _seekThresholdMs ||
        deltaMs < -_seekThresholdMs;
    if (seeked) {
      _generation++; // 在途延迟回调作废
      // 锚点取落点秒 - 1：下一个 tick 补发落点秒的弹幕（内容不丢）
      _lastEmittedSecond = second - 1;
      return const DanmakuTickResult([], true);
    }

    final entries = <DanmakuEntry>[];
    if (second > last) {
      for (var s = last + 1; s <= second; s++) {
        final bucket = _buckets[s];
        if (bucket != null) entries.addAll(bucket);
      }
      // 锚点只进不退：微幅回抖（未达 seek 阈值）不重发已发射的桶
      _lastEmittedSecond = second;
    }
    return DanmakuTickResult(entries, false);
  }
}
