/// 弹幕控制器（业务层，弹幕移植方案阶段2+阶段3）：绑定共享 [Player]，
/// 驱动本地同名弹幕的加载（9 种命名规则 + B站 XML 后台解析）与
/// 网络弹幕（弹弹Play 搜索选中 / 自动匹配 / 切集自动匹配，下载落盘 +
/// 记忆持久化）、1s tick 秒桶调度发射（六守卫）、canvas_danmaku 渲染层的
/// 挂载/显隐/暂停恢复/倍速跟随。
///
/// 横竖屏播放页共享同一实例（同一 Player）；两个页面各自的
/// [DanmakuScreen] 通过 attachLayer/detachLayer 注册到本控制器，
/// 切换横竖屏时无需清屏重启（两侧渲染层同步驱动，返回时画面无缝）。
///
/// 阶段2 约定（工作.md 弹幕第 4 点）：样式与配置全部由 [DanmakuSettings]
/// 驱动（单例 ChangeNotifier + 持久化），控制器订阅后映射到
/// canvas_danmaku 的 DanmakuOption（updateOption 热更新）；弹幕开关仍为
/// 会话级状态（不持久化，默认开启）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/danmaku_auto_match_cache.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/services/danmaku_auto_match_cache_store.dart';
import 'package:moumou/services/danmaku_memory.dart';
import 'package:moumou/services/danmaku_network_service.dart';
import 'package:moumou/services/danmaku_scheduler.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:moumou/services/danmaku_settings.dart';
import 'package:moumou/utils/danmaku_dedup.dart';
import 'package:moumou/utils/danmaku_episode.dart';
import 'package:moumou/utils/danmaku_local_file.dart';
import 'package:moumou/utils/danmaku_random_color.dart';
import 'package:moumou/utils/danmaku_timeline.dart';
import 'package:moumou/utils/danmaku_xml.dart';
import 'package:path/path.dart' as p;

/// 弹幕设置 → canvas DanmakuOption 的映射（渲染层初始值与业务层热更新共用，
/// 单一事实来源）。样式（字号/字重/描边/不透明度）+ 配置（区域/行高/三类
/// 显隐/海量）全量映射；速度（duration/staticDuration）由控制器按倍速叠加
/// （见 [_buildOption]），不在此处设置。
canvas.DanmakuOption danmakuOptionFromSettings(DanmakuSettings s) {
  return canvas.DanmakuOption(
    fontSize: s.fontSize,
    fontWeight: s.fontWeight,
    area: s.area,
    opacity: s.opacity,
    strokeWidth: s.strokeWidth,
    lineHeight: s.lineHeight,
    hideTop: !s.showTop,
    hideBottom: !s.showBottom,
    hideScroll: !s.showScroll,
    massiveMode: s.massiveMode,
  );
}

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
    // 阶段2：订阅弹幕设置（面板/全局改动 → 实时应用）
    DanmakuSettings.instance.addListener(_onSettingsChanged);
    _lastDedup = _settings.deduplication;
    _lastRandomColor = _settings.randomColor;
    _lastTimeOffset = _settings.timeOffsetSeconds;
  }

  final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  late final Timer _timer;
  final DanmakuScheduler _scheduler = DanmakuScheduler();

  /// 弹幕设置单例（样式/配置全部由它驱动，阶段2）
  final DanmakuSettings _settings = DanmakuSettings.instance;

  /// 原始弹幕条目（当前已装载文件的全部数据；去重开/关时按它重灌秒桶）
  List<DanmakuEntry> _rawEntries = const [];

  /// 随机渐变色推进器（随机色开启期间逐条生成；关闭→开启重建）
  DanmakuColorWheel? _colorWheel;

  /// 上次同步的去重/随机色开关（仅开关变化时才清屏重灌，
  /// 避免拖动其他滑杆时在屏弹幕被反复清掉闪屏）
  bool _lastDedup = false;
  bool _lastRandomColor = false;

  /// 上次同步的时间轴偏移（偏移变化时重锚定秒桶 + 清屏，弹幕按新偏移对齐）
  double _lastTimeOffset = 0;

  /// 手动导入记忆（按视频路径持久化，重启播放器/软件后自动恢复）
  final DanmakuManualMemory _memory = DanmakuManualMemory();

  /// 弹幕网络服务（弹弹Play：搜索 / 自动匹配 / 拉取，阶段3 网络弹幕）
  final DanmakuNetworkService _network = DanmakuNetworkService();

  /// 自动匹配缓存（切集自动匹配弹幕，工作.md 第 7 点）
  final DanmakuAutoMatchCacheStore _autoMatchCache = DanmakuAutoMatchCacheStore();

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
      _scheduler.notifySeeked(_sourcePosition(position));
      _clearLayers();
    }
  }

  /// 自动加载弹幕成功后的回调（参数为弹幕文件名），由播放页注入以弹提示。
  /// 同名自动加载与手动导入记忆恢复共用；服务层不依赖 UI，
  /// 对齐 SubtitleController.onAutoLoadedSubtitle。
  void Function(String fileName)? onAutoLoadedDanmaku;

  /// 网络弹幕（弹弹Play 搜索 / 自动匹配 / 切集自动匹配）加载成功后的回调
  /// （参数为提示文案，如「番剧名 · 第02话」），由播放页注入以弹提示。
  void Function(String message)? onNetworkDanmakuLoaded;

  bool get danmakuOn => _danmakuOn;

  /// 当前已装载的弹幕总条数（提示用；未装载为 0）。
  /// 去重开启时为合并后的条数（与实际发射一致）。
  int get danmakuCount => _scheduler.danmakuCount;

  // ── 设置响应（阶段2：DanmakuSettings → DanmakuOption 映射）──

  /// 设置变化：样式/配置经 updateOption 热更新。字号/字重/描边是
  /// 「重栅格化」项（canvas 会全量清屏重绘），由设置面板在**松手时**才提交
  /// （见 player_danmaku_settings_panel.dart 的 _CommitSliderTile），所以这里
  /// 无需再逐帧去抖；其余轻量项（不透明度/区域/行高/速度/显隐）实时下发。
  /// 仅去重/随机色开关变化时才重灌秒桶/重建色轮并清屏。
  void _onSettingsChanged() {
    if (_disposed) return;
    _applyOption();
    final dedupChanged = _settings.deduplication != _lastDedup;
    final randomChanged = _settings.randomColor != _lastRandomColor;
    final offsetChanged = _settings.timeOffsetSeconds != _lastTimeOffset;
    _lastDedup = _settings.deduplication;
    _lastRandomColor = _settings.randomColor;
    _lastTimeOffset = _settings.timeOffsetSeconds;
    if (dedupChanged) {
      _refeedIfLoaded();
    }
    if (randomChanged) {
      // 随机色轮重建：开启时新建（新随机起点），关闭时释放（发射不再取色）
      _colorWheel = _settings.randomColor ? DanmakuColorWheel() : null;
      _clearLayers();
    }
    if (offsetChanged) {
      // 时间轴偏移变化：重锚定秒桶 + 清屏，在屏/待发弹幕按新偏移重新对齐
      _scheduler.notifySeeked(_sourcePosition(_position));
      _clearLayers();
    }
  }

  /// 去重开关变化时重灌秒桶：按原始条目重新合并再喂给调度器，并锚定
  /// 当前位置（下个 tick 从当前秒继续，不倾倒历史弹幕）。
  void _refeedIfLoaded() {
    if (!_hasDanmaku) return;
    final entries = _effectiveEntries(_rawEntries);
    _scheduler.reset();
    _scheduler.feed(entries);
    _scheduler.notifySeeked(_sourcePosition(_position));
    _clearLayers();
  }

  /// 时间轴偏移后的源时间位置（对齐 Kazumi：source = playback − offset；
  /// 结果可为负，负秒桶在调度器中为空，即片头前无弹幕）。
  Duration _sourcePosition(Duration playbackPosition) {
    return sourceDanmakuPosition(
      playbackPosition,
      _settings.timeOffsetSeconds,
    );
  }

  /// 应用当前设置（样式/配置 → 渲染层；发射侧字段实时读取设置单例）。
  /// 渲染层未挂载时无需下发（attachLayer 挂载时会应用一次）。
  void _applyOption() {
    if (_disposed) return;
    for (final layer in _layers) {
      _applyOptionTo(layer);
    }
  }

  /// 去重开关生效后的条目集（关 = 原样；开 = 时间窗合并）
  List<DanmakuEntry> _effectiveEntries(List<DanmakuEntry> entries) {
    if (!_settings.deduplication) return entries;
    return dedupeDanmakuEntries(entries);
  }

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
  /// 优先级：**记忆恢复（静默）→ 同名自动查找（首次弹 toast）→ 网络自动
  /// 匹配（切集自动匹配开关）**。记忆里同时存有手动导入与网络弹幕落盘
  /// 文件（工作.md 第 2 点：成功装载过一次即持久化），恢复不弹「已自动
  /// 加载」提示。切集竞态防护：进入即开新会话并重置调度器（清桶 + 清屏），
  /// 异步读取/解析完成后会话号已变则丢弃。
  Future<void> loadForVideo(String mediaPath) async {
    final session = ++_loadSession;
    _currentMediaPath = mediaPath;
    _scheduler.reset();
    _clearLayers();
    _hasDanmaku = false;
    // 1. 手动导入记忆：命中即恢复（重启播放器/软件无需重新选择）。
    //    **记忆恢复一律静默**——记忆里既有手动导入、也有网络弹幕/自动匹配
    //    的落盘文件，都是用户显式选择或已提示过的结果，不能弹「已自动加载」
    //    提示（工作.md 第 3 点：手动加载后重启误报自动加载的 bug）。
    final remembered = await _memory.get(mediaPath);
    if (_disposed) return;
    if (remembered != null && session == _loadSession) {
      final ok = await _tryLoadFile(remembered, session);
      if (ok) return;
      if (_disposed || session != _loadSession) return;
      // 记忆的弹幕文件已失效（被删除/不可读/空弹幕）→ 清除记忆，
      // 回落同名自动查找（小喵 player 卡记忆死路径的教训）
      await _memory.remove(mediaPath);
    }
    // 2. 同名自动查找（9 种命名规则，B站 XML）
    final loaded = await _loadLocalDanmaku(mediaPath);
    if (_disposed || session != _loadSession) return;
    if (loaded == null) {
      // 3. 本地无匹配：尝试网络自动匹配（切集自动匹配弹幕，工作.md 第 7 点）
      await _tryAutoMatch(session);
      return;
    }
    _feedEntries(loaded.entries);
    _hasDanmaku = loaded.entries.isNotEmpty;
    if (loaded.entries.isNotEmpty) {
      await _notifyAutoLoaded(loaded.fileName);
    }
  }

  /// 装载弹幕数据：保留原始条目（去重开/关重灌用）+ 按当前设置合并后
  /// 喂给调度器 + 重置随机色轮（同文件每次加载重新随机起点）
  void _feedEntries(List<DanmakuEntry> entries) {
    _rawEntries = List.of(entries);
    // 随机色开启时每次装载重建色轮：新随机起点，同内容不重样
    _colorWheel = _settings.randomColor ? DanmakuColorWheel() : null;
    _scheduler.feed(_effectiveEntries(entries));
  }

  /// 同名自动加载成功通知（**仅同名自动查找路径**；记忆恢复/手动导入
  /// 静默——见 loadForVideo 第 1 步说明）。每个视频只在**第一次**自动
  /// 加载时提示（持久化去重，重启不再重复）。
  Future<void> _notifyAutoLoaded(String fileName) async {
    final mediaPath = _currentMediaPath;
    if (mediaPath != null) {
      if (await _memory.hasShownAutoLoadToast(mediaPath)) return;
      await _memory.markAutoLoadToastShown(mediaPath);
    }
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
      _feedEntries(entries);
      _hasDanmaku = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 网络弹幕 / 自动匹配（阶段3：弹弹Play 开放弹幕网络）──────────

  /// 下载并装载网络弹幕（弹弹Play 搜索选中 / 自动匹配命中共用）。
  /// 成功返回 true（触发 [onNetworkDanmakuLoaded]），并自动开启弹幕显示；
  /// 同时生成 B站 XML 落盘并记忆到当前视频（重启播放/软件自动恢复，
  /// 与切集自动匹配开关无关，工作.md 第 2 点）。
  /// 会话号保护：在途网络请求与后续切集竞态时结果判废。
  Future<bool> loadNetworkDanmaku({
    required int episodeId,
    required String animeTitle,
    required String episodeTitle,
    String? serverUrl,
  }) async {
    final session = ++_loadSession;
    _scheduler.reset();
    _clearLayers();
    _hasDanmaku = false;
    ({List<DanmakuEntry> entries, String? filePathOrNull}) download;
    try {
      download = await _network.downloadEpisode(
        episodeId: episodeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        serverUrl: serverUrl,
      );
    } catch (_) {
      download = (entries: const [], filePathOrNull: null);
    }
    if (_disposed || session != _loadSession) return false;
    if (download.entries.isEmpty) return false;
    _feedEntries(download.entries);
    _hasDanmaku = true;
    if (!_danmakuOn) {
      _danmakuOn = true;
      notifyListeners();
    }
    // 持久化记忆（工作.md 第 2 点）：网络弹幕落盘后按视频路径记忆，
    // 重启播放/软件与 loadForVideo 第 1 步（手动记忆）同一恢复路径，
    // 与「切集自动匹配」开关无关。
    await _rememberDownload(download.filePathOrNull);
    onNetworkDanmakuLoaded?.call('$animeTitle · $episodeTitle');
    return true;
  }

  /// 对当前视频发起自动匹配（「自动匹配」按钮）：计算文件哈希 + 向所有
  /// 启用服务器匹配，返回候选列表（空 = 无匹配 / 失败）。
  Future<List<DanmakuMatchItem>> matchCurrentVideo() async {
    final path = _currentMediaPath;
    if (path == null) return const [];
    try {
      final hash = await _network.calculateFileHash(path);
      if (hash == null) return const [];
      final file = File(path);
      final size = await file.length();
      return _network.matchVideo(
        fileName: p.basename(path),
        fileHash: hash,
        fileSize: size,
      );
    } catch (_) {
      return const [];
    }
  }

  /// 保存自动匹配缓存（选中某番剧后记录其完整集列表，供切集自动匹配）。
  Future<void> saveAutoMatchCache({
    required int animeId,
    required String animeTitle,
    required String? serverUrl,
    required List<DandanEpisode> episodes,
  }) async {
    await _autoMatchCache.save(DanmakuAutoMatchCache(
      animeId: animeId,
      animeTitle: animeTitle,
      serverUrl: serverUrl,
      episodes: episodes,
    ));
  }

  /// 通过番剧名 + animeId 取回完整集列表（自动匹配命中后保存切集缓存用）。
  Future<List<DandanEpisode>?> fetchAnimeEpisodes({
    required int animeId,
    required String animeTitle,
    String? serverUrl,
  }) async {
    try {
      return await _network.fetchAnimeEpisodesById(
        animeId,
        animeTitle,
        serverUrl: serverUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// 切集自动匹配（loadForVideo 本地无弹幕后调用）：开启开关 + 存在缓存时，
  /// 从文件名提取集数 → 在缓存集列表中定位对应集 → 拉取并装载弹幕。
  /// 装载成功同样落盘记忆（该视频之后再进直接走记忆恢复，不再依赖开关）。
  ///
  /// `autoMatchEnabled` 已内含「默认弹弹Play 服务器启用时不生效」的互斥判定
  /// （工作.md 第 7 点），此处无需再判一次——互斥只在服务层裁决一处。
  Future<void> _tryAutoMatch(int session) async {
    if (!DanmakuServerSettings.instance.autoMatchEnabled) return;
    final cache = await _autoMatchCache.load();
    if (_disposed || session != _loadSession || cache == null) return;
    final path = _currentMediaPath;
    if (path == null) return;
    final episodeNumber = extractEpisodeNumber(p.basename(path));
    if (episodeNumber == null) return;
    final matched = findMatchingEpisode(cache.episodes, episodeNumber);
    if (matched == null) return;
    ({List<DanmakuEntry> entries, String? filePathOrNull}) download;
    try {
      download = await _network.downloadEpisode(
        episodeId: matched.episodeId,
        animeTitle: cache.animeTitle,
        episodeTitle: matched.episodeTitle,
        serverUrl: cache.serverUrl,
      );
    } catch (_) {
      download = (entries: const [], filePathOrNull: null);
    }
    if (_disposed || session != _loadSession) return;
    if (download.entries.isEmpty) return;
    _feedEntries(download.entries);
    _hasDanmaku = true;
    if (!_danmakuOn) {
      _danmakuOn = true;
      notifyListeners();
    }
    await _rememberDownload(download.filePathOrNull);
    onNetworkDanmakuLoaded?.call('${cache.animeTitle} ${matched.episodeTitle}');
  }

  /// 把网络弹幕落盘文件记忆到当前视频（工作.md 第 2 点：无论本地导入、
  /// 自动匹配还是网络搜索下载，成功装载过一次即持久化记忆）。落盘失败
  /// （filePathOrNull 为 null）跳过记忆，本次会话仍正常播放。
  Future<void> _rememberDownload(String? filePath) async {
    if (filePath == null) return;
    final mediaPath = _currentMediaPath;
    if (mediaPath == null) return;
    await _memory.set(mediaPath, filePath);
  }

  // ── 1s tick 发射（守卫链对齐 Kazumi 六守卫，减去阶段1 未有的屏蔽词）──

  void _onTick() {
    if (_disposed) return;
    if (!_enginePlaying || _buffering || !_danmakuOn || !_hasDanmaku) return;
    final result = _scheduler.onTick(_sourcePosition(_position), _rate);
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
      // 随机渐变色开启：忽略文件颜色，逐条生成（关闭 = 文件原色）
      color: Color(0xFF000000 | (_colorWheel?.nextColor() ?? entry.color)),
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

  /// 应用完整弹幕选项（样式 + 配置 + 速度）到单个渲染层。
  /// 速度语义：duration = 弹幕速度基准 / rate（updateOption 全局平滑变速，
  /// 在屏弹幕同帧变速、无位置跳变；基准独立存储，连续切倍速零累计误差）。
  /// 样式/配置字段经 [danmakuOptionFromSettings] 全量映射（阶段2：面板改值
  /// 热更新，字号/字重/描边/不透明度/区域/行高/三类显隐/海量全部生效）。
  void _applyOptionTo(canvas.DanmakuController<void> layer) {
    layer.updateOption(_buildOption());
  }

  /// 从设置单例构建完整 DanmakuOption（样式 + 配置），再叠加速度
  /// （duration/staticDuration 按倍速缩放）。渲染层初始值与热更新共用。
  canvas.DanmakuOption _buildOption() {
    return danmakuOptionFromSettings(_settings).copyWith(
      duration: _settings.scrollSeconds / _rate,
      staticDuration: _settings.scrollSeconds / 2 / _rate,
    );
  }

  void _clearLayers() {
    for (final layer in _layers) {
      layer.clear();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    DanmakuSettings.instance.removeListener(_onSettingsChanged);
    _timer.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _layers.clear();
    _scheduler.reset();
    super.dispose();
  }
}
