import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/utils/intro_outro_skip.dart';

/// 片头片尾自动跳过状态跟踪器：由播放位置流驱动，维护「媒体已就绪 /
/// 片头已处理 / 片尾已处理」三态，横竖屏播放页共享同一实例。
///
/// - 打开媒体前调用 [reset]，openAndRestore 完成后依次调用
///   [markResumedPosition]（恢复进度时）与 [markReady]，此后位置流
///   每次更新调用 [onPositionChanged]（纯计算，返回应执行的动作）；
/// - 每集片头/片尾各触发一次（对齐小喵 player 的 hasSkippedIntro /
///   hasShownOutroWarning）：动作一旦返回即标记 handled，seek / 切集
///   的异步窗口内重复位置事件不会重复触发；
/// - 恢复进度感知：恢复点 > 0 时预标记片头已处理（尊重恢复位置，
///   不立即跳片头）；恢复点落在片尾范围内时预标记片尾已处理（防止
///   恢复后马上被抛到下一集）；
/// - 位置越过片头范围即标记片头已处理：用户主动 seek 越过片头后
///   回拖进片头范围不会再次被跳走。
class IntroOutroTracker {
  IntroOutroTracker(this._settings);

  final IntroOutroSettings _settings;

  /// 媒体是否已就绪（openAndRestore 完成前位置事件不评估，对齐
  /// KT 的 isVideoReady/markVideoReady 门控）
  bool _ready = false;

  /// 当前媒体片头是否已处理（跳过过一次或恢复/越过片头）
  bool _introHandled = false;

  /// 当前媒体片尾是否已处理（跳集过一次或恢复点落在片尾）
  bool _outroHandled = false;

  /// 打开媒体 / 切集前调用：立即清空状态（不等 open 完成，
  /// 避免旧媒体状态残留）
  void reset() {
    _ready = false;
    _introHandled = false;
    _outroHandled = false;
  }

  /// openAndRestore 完成后调用：位置事件开始参与评估
  void markReady() {
    _ready = true;
  }

  /// 恢复进度感知：openAndRestore 恢复完成后调用一次。
  ///
  /// - 恢复点 > 0：预标记片头已处理（尊重用户恢复位置，不跳片头）；
  /// - 恢复点落在片尾范围内：预标记片尾已处理（不立即切集）。
  void markResumedPosition(Duration position, Duration duration) {
    final pos = position.inMilliseconds / 1000.0;
    if (pos > 0) {
      _introHandled = true;
    }
    final dur = duration.inMilliseconds / 1000.0;
    if (dur > 0 &&
        _settings.outroSeconds > 0 &&
        pos >= dur - _settings.outroSeconds) {
      _outroHandled = true;
    }
  }

  /// 位置流每次更新调用（高频）：返回本次位置应执行的片头片尾动作，
  /// 无动作返回 [IntroOutroAction.none]。
  IntroOutroAction onPositionChanged(
    Duration position,
    Duration duration, {
    required bool hasNext,
  }) {
    if (!_ready) return IntroOutroAction.none;
    final pos = position.inMilliseconds / 1000.0;
    final dur = duration.inMilliseconds / 1000.0;
    if (dur <= 0) return IntroOutroAction.none;
    // 越过片头范围即标记已处理：seek 越过片头后回拖不重复跳
    if (_settings.introSeconds > 0 &&
        !_introHandled &&
        pos >= _settings.introSeconds) {
      _introHandled = true;
    }
    final action = resolveIntroOutroAction(
      enabled: _settings.enabled,
      introSeconds: _settings.introSeconds,
      outroSeconds: _settings.outroSeconds,
      positionSeconds: pos,
      durationSeconds: dur,
      introHandled: _introHandled,
      outroHandled: _outroHandled,
      hasNext: hasNext,
    );
    // 动作一旦产生即标记，seek / 切集异步窗口内不重复触发
    switch (action) {
      case IntroOutroAction.skipIntro:
        _introHandled = true;
      case IntroOutroAction.nextEpisode:
        _outroHandled = true;
      case IntroOutroAction.none:
        break;
    }
    return action;
  }
}
