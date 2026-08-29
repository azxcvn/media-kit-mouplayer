/// 弹幕控制器（业务层，弹幕移植方案阶段1）：绑定共享 [Player]，
/// 驱动本地同名弹幕的加载（9 种命名规则 + B站 XML 后台解析）、
/// 1s tick 秒桶调度发射（六守卫）、canvas_danmaku 渲染层的
/// 挂载/显隐/暂停恢复/倍速跟随。
///
/// 横竖屏播放页共享同一实例（同一 Player）；两个页面各自的
/// [DanmakuScreen] 通过 attachLayer/detachLayer 注册到本控制器，
/// 切换横竖屏时无需清屏重启（两侧渲染层同步驱动，返回时画面无缝）。
///
/// 阶段1 约定（工作.md 弹幕第 2 点）：弹幕样式/字体/各项配置全部使用
/// canvas_danmaku 默认值（仅倍速跟随按 rate 缩放 duration/staticDuration）；
/// 弹幕开关为会话级状态（不持久化，默认开启）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/services/danmaku_memory.dart';
import 'package:moumou/services/danmaku_scheduler.dart';
import 'package:moumou/utils/danmaku_local_file.dart';
import 'package:moumou/utils/danmaku_timeline.dart';
import 'package:moumou/utils/danmaku_xml.dart';
import 'package:path/path.dart' as p;

class DanmakuController extends ChangeNotifier {
  DanmakuController(this._player) {
    // 从共享播放器当前状态初始化（流是广播流，迟订阅不重放当前值）
    _rate = _player.state.rate;
    _enginePlaying = _player.state.playing;
    _buffering = _player.state.buffering;
    _position = _player.state.position;
    _subs.add(_player.stream.position.listen(_onPositionEvent));
    _subs.add(_player.stream.playing.listen((v) {
      _enginePlaying = v;
      _syncPlaying();
    }));
    _subs.add(_player.stream.buffering.listen((v) => _buffering = v));
    _subs.add(_player.stream.rate.listen((v) {
      _rate = v;
      _applyOption();
    }));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  late final Timer _timer;
  final DanmakuScheduler _scheduler = DanmakuScheduler();

  /// 手动导入记忆（按视频路径持久化，重启播放器/软件后自动恢复）
  final DanmakuManualMemory _memory = DanmakuManualMemory();

  /// 渲染层注册表（横竖屏页各挂一个 DanmakuScreen，同步驱动）
  final List<canvas.DanmakuController<void>> _layers = [];

  Duration _position = Duration.zero;
  bool _enginePlaying = false;
  bool _buffering = false;
  double _rate = 1.0;

  /// 弹幕显示开关（会话级，不持久化；默认开启——加载到弹幕即显示）
  bool _danmakuOn = true;

  /// 当前视频是否装载了弹幕数据
  bool _hasDanmaku = false;

  bool _disposed = false;

  /// 加载会话号：切集/重开时自增，在途的异步加载结果按它判废
  /// （对齐 Kazumi AsyncSessionOwner 的拉取层失效语义）
  int _loadSession = 0;

  /// 当前播放的视频路径（手动导入记忆的键）
  String? _currentMediaPath;

  // ── 位置流实时 seek 检测（Kazumi 体验：seek 松手瞬间即清屏）──
  // 1s tick 的跳变检测是兜底；这里在每次位置事件上即时判定：
  // 以「当前倍速 × 事件间隔墙钟时间」为期望位移，反向超阈值或正向
  // 超出期望 + 松弛量 → 立即代数失效（旧批次在途回调作废）+ 清屏 +
  // 锚点对齐，不再等下一个 tick。

  /// 单调时钟（事件间隔测量；不受系统时间回拨影响）
  final Stopwatch _positionClock = Stopwatch()..start();

  /// 上次位置流事件的缓存（seek 判定基准）
  Duration? _lastStreamEventPosition;
  int? _lastStreamEventElapsedMs;

  /// 位置流事件处理：缓存位置 + 实时 seek 检测
  void _onPositionEvent(Duration position) {
    _position = position;
    final previous = _lastStreamEventPosition;
    final previousElapsedMs = _lastStreamEventElapsedMs;
    final elapsedMs = _positionClock.elapsedMilliseconds;
    _lastStreamEventPosition = position;
    _lastStreamEventElapsedMs = elapsedMs;
    // 无弹幕数据时清屏无意义（判定基准仍持续更新）
    if (_disposed || previous == null || previousElapsedMs == null) return;
    if (!_hasDanmaku) return;
    final seeked = DanmakuScheduler.isSeekJump(
      previousPosition: previous,
      currentPosition: position,
      elapsedMs: elapsedMs - previousElapsedMs,
      rate: _rate,
    );
    if (seeked) {
      _scheduler.notifySeeked(position);
      _clearLayers();
    }
  }

  /// 自动加载弹幕成功后的回调（参数为弹幕文件名），由播放页注入以弹提示。
  /// 同名自动加载与手动导入记忆恢复共用；服务层不依赖 UI，
  /// 对齐 SubtitleController.onAutoLoadedSubtitle。
  void Function(String fileName)? onAutoLoadedDanmaku;

  bool get danmakuOn => _danmakuOn;

  /// 当前已装载的弹幕总条数（提示用；未装载为 0）
  int get danmakuCount => _scheduler.danmakuCount;

  /// 弹幕速度基准（canvas_danmaku 默认值；本阶段不做配置）
  static const double _baseDuration = 10;
  static const double _baseStaticDuration = 5;

  // ── 渲染层挂载（页面 Stack 内 DanmakuScreen 的 createdController 回调）──

  void attachLayer(canvas.DanmakuController<void> layer) {
    _layers.add(layer);
    _applyOptionTo(layer);
    if (!_enginePlaying) layer.pause();
  }

  /// 页面卸载 DanmakuScreen 时移除（竖屏页 pop 返回横屏，渲染层归一）
  void detachLayer(canvas.DanmakuController<void> layer) {
    _layers.remove(layer);
  }

  // ── 显隐开关（工作.md 弹幕第 2 点：弹幕的显示与隐藏）──

  void toggle() => setDanmakuOn(!_danmakuOn);

  void setDanmakuOn(bool value) {
    if (_danmakuOn == value) return;
    _danmakuOn = value;
    if (!value) {
      // 关闭：作废在途发射回调 + 清屏（开启后从当前位置继续，不回放）
      _scheduler.invalidate();
      _clearLayers();
    }
    notifyListeners();
  }

  // ── 本地弹幕加载（首开 / 切集统一入口）──

  /// 加载视频的弹幕（首开 / 切集统一入口）。
  ///
  /// 优先级：**手动导入记忆 → 同名自动查找**（用户显式选择不被自动查找
  /// 覆盖，对齐字幕外挂记忆语义）。切集竞态防护：进入即开新会话并重置
  /// 调度器（清桶 + 清屏），异步读取/解析完成后会话号已变则丢弃。
  Future<void> loadForVideo(String mediaPath) async {
    final session = ++_loadSession;
    _currentMediaPath = mediaPath;
    _scheduler.reset();
    _clearLayers();
    _hasDanmaku = false;
    // 1. 手动导入记忆：命中即恢复（重启播放器/软件无需重新选择）
    final remembered = await _memory.get(mediaPath);
    if (_disposed) return;
    if (remembered != null && session == _loadSession) {
      final ok = await _tryLoadFile(remembered, session);
      if (ok) {
        _notifyAutoLoaded(p.basename(remembered));
        return;
      }
      if (_disposed || session != _loadSession) return;
      // 记忆的弹幕文件已失效（被删除/不可读/空弹幕）→ 清除记忆，
      // 回落同名自动查找（小喵 player 卡记忆死路径的教训）
      await _memory.remove(mediaPath);
    }
    // 2. 同名自动查找（9 种命名规则，B站 XML）
    final loaded = await _loadLocalDanmaku(mediaPath);
    if (_disposed || session != _loadSession) return;
    if (loaded == null) return; // 未找到 / 解析失败：无弹幕继续播放
    _scheduler.feed(loaded.entries);
    _hasDanmaku = loaded.entries.isNotEmpty;
    if (loaded.entries.isNotEmpty) {
      _notifyAutoLoaded(loaded.fileName);
    }
  }

  /// 自动加载成功通知（同名 / 记忆恢复共用；回调未注入时静默）
  void _notifyAutoLoaded(String fileName) {
    onAutoLoadedDanmaku?.call(fileName);
  }

  /// 扫描同目录并解析同名弹幕文件；无匹配 / 失败返回 null。
  Future<({List<DanmakuEntry> entries, String fileName})?>
      _loadLocalDanmaku(String mediaPath) async {
    try {
      final videoFile = File(mediaPath);
      if (!videoFile.existsSync()) return null;
      final videoName = p.basename(mediaPath);
      final videoBase = p.basenameWithoutExtension(mediaPath);
      if (videoBase.isEmpty) return null;
      final names = <String>[];
      await for (final e in videoFile.parent.list()) {
        if (e is File) names.add(p.basename(e.path));
      }
      final found = findLocalDanmakuFileName(videoBase, videoName, names);
      if (found == null) return null;
      final content =
          await File(p.join(videoFile.parent.path, found)).readAsString();
      if (content.isEmpty) return null;
      // 大文件（整集弹幕可达数 MB）放后台 isolate 解析；
      // compute 只捕获原始值（§7 坑表：闭包捕获不可发送对象会崩）
      final entries = await compute(parseDanmakuXml, content);
      return (entries: entries, fileName: found);
    } catch (_) {
      return null;
    }
  }

  /// 手动加载本地弹幕文件（播放器「更多 → 弹幕 → 本地弹幕」的文件选择器
  /// 路径）。[path] 必须是可直接读取的真实绝对路径（系统选择器的
  /// content:// 已由原生侧拷贝到 filesDir/danmaku/）。
  ///
  /// 加载成功返回 true：记忆到当前视频（重启播放器/软件后自动恢复）并
  /// 自动开启弹幕显示（手动导入即用户想看的意图）；文件不可读 / 无有效
  /// 弹幕条目返回 false（空弹幕文件视为失败，提示检查格式而非看不到弹幕）。
  Future<bool> loadDanmakuFromFile(String path) async {
    final session = ++_loadSession;
    _scheduler.reset();
    _clearLayers();
    _hasDanmaku = false;
    final ok = await _tryLoadFile(path, session);
    if (_disposed || !ok) return false;
    final mediaPath = _currentMediaPath;
    if (mediaPath != null) {
      await _memory.set(mediaPath, path);
    }
    if (!_danmakuOn) {
      _danmakuOn = true;
      notifyListeners();
    }
    return true;
  }

  /// 读取并解析单个弹幕文件，装载到调度器；返回是否成功装载。
  /// 会话号不匹配时丢弃结果（切集竞态），装载动作受会话号保护。
  Future<bool> _tryLoadFile(String path, int session) async {
    try {
      final content = await File(path).readAsString();
      if (_disposed || session != _loadSession || content.isEmpty) {
        return false;
      }
      final entries = await compute(parseDanmakuXml, content);
      if (_disposed || session != _loadSession) return false;
      if (entries.isEmpty) return false;
      _scheduler.feed(entries);
      _hasDanmaku = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 1s tick 发射（守卫链对齐 Kazumi 六守卫，减去阶段1 未有的屏蔽词）──

  void _onTick() {
    if (_disposed) return;
    if (!_enginePlaying || _buffering || !_danmakuOn || !_hasDanmaku) return;
    final result = _scheduler.onTick(_position, _rate);
    if (result.seeked) _clearLayers();
    final entries = result.entries;
    if (entries.isEmpty) return;
    final generation = _scheduler.generation;
    final total = entries.length;
    for (var i = 0; i < entries.length; i++) {
      final delay = staggerDelayMilliseconds(index: i, total: total);
      Future.delayed(Duration(milliseconds: delay), () {
        if (_disposed ||
            !_enginePlaying ||
            _buffering ||
            !_danmakuOn ||
            _scheduler.generation != generation) {
          return;
        }
        _addEntry(entries[i]);
      });
    }
  }

  void _addEntry(DanmakuEntry entry) {
    if (_layers.isEmpty) return;
    final item = canvas.DanmakuContentItem<void>(
      entry.text,
      color: Color(0xFF000000 | entry.color),
      type: itemTypeForMode(entry.mode),
    );
    for (final layer in _layers) {
      layer.addDanmaku(item);
    }
  }

  /// B站模式 → 渲染类型：4 底部 / 5 顶部，其余一律滚动
  /// （对齐 Kazumi `_danmakuItemType`；高级弹幕后续阶段再接）
  static canvas.DanmakuItemType itemTypeForMode(int mode) {
    if (mode == 4) return canvas.DanmakuItemType.bottom;
    if (mode == 5) return canvas.DanmakuItemType.top;
    return canvas.DanmakuItemType.scroll;
  }

  // ── 播放暂停 / 倍速跟随 ──

  void _syncPlaying() {
    if (_disposed) return;
    for (final layer in _layers) {
      if (_enginePlaying) {
        layer.resume();
      } else {
        layer.pause();
      }
    }
  }

  /// 倍速跟随：duration = 基准 / rate（updateOption 全局平滑变速，
  /// 在屏弹幕同帧变速、无位置跳变；基准独立存储，连续切倍速零累计误差）
  void _applyOption() {
    if (_disposed) return;
    for (final layer in _layers) {
      _applyOptionTo(layer);
    }
  }

  void _applyOptionTo(canvas.DanmakuController<void> layer) {
    layer.updateOption(layer.option.copyWith(
      duration: _baseDuration / _rate,
      staticDuration: _baseStaticDuration / _rate,
    ));
  }

  void _clearLayers() {
    for (final layer in _layers) {
      layer.clear();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _layers.clear();
    _scheduler.reset();
    super.dispose();
  }
}
