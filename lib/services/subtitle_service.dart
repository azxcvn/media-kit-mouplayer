import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:moumou/models/subtitle_track.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/subtitle_settings.dart';

/// 默认内置思源黑体家族名（Android libass 兜底中文字体）
const String kDefaultFontName = 'Noto Sans CJK SC';

/// 字幕控制器：绑定单个播放器（横竖屏共享同一实例），
/// 维护「轨道列表 / 当前字幕轨道 / 外挂字幕路径」状态并直接驱动 mpv。
///
/// - **单选模型**（只允许同时启用一条字幕轨道，参考 mpv `sid`）；
/// - 外挂字幕按视频路径（`mediaPath`）独立隔离存储，避免 A 视频字幕串到 B 视频；
/// - 记录并持久化每个视频最后选中的字幕轨道，重开视频自动恢复选中；
/// - mpv 属性与命令（参考 mpvRx 的 SubtitleStyle / PlaybackSession）：
///   - 轨道列表：`track-list/count` + `track-list/$i/{type,id,title,lang,codec,external,selected}`；
///   - 当前字幕：`sid`（id 或 'no'；打开文件后 mpv 会自动选一条轨道，
///     [reload] 会把 [primary] 同步成 mpv 实际生效的 sid，保证 UI 选中态）；
///   - 外挂字幕：`sub-add <path> <flags>`（'select' = 立即选中；'auto' = 无字幕时才选，
///     重开文件恢复用），`sub-remove <id>` 移除；
///   - 设置：[SubtitleSettings] 各值映射 `sub-delay` / `sub-scale` / `sub-pos` /
///     `sub-color` / `sub-border-*` / `sub-back-color` / `sub-font` / `sub-ass-override`。
///
/// 内嵌样式策略：
/// - 未开启「强制覆盖内嵌样式」时（默认），`sub-ass-override` 设为 `scale`
///   （保留 ASS 原生字体、特效、位置和排版，同时响应缩放调节）；
/// - 开启「强制覆盖内嵌样式」时，`sub-ass-override` 设为 `force`（用户样式强制生效）。
/// - 普通文本字幕（SRT/VTT）在 scale 和 force 模式下均能正常响应用户样式。
class SubtitleController extends ChangeNotifier {
  SubtitleController(this._player, {SubtitleSettings? settings})
      : _settings = settings ?? SubtitleSettings.instance {
    // 监听 media_kit 轨道流：mpv 解复用完成或轨道变动时自动刷新
    _tracksSubscription = _player.stream.tracks.listen((_) {
      reload();
    });
  }

  final Player _player;
  final SubtitleSettings _settings;
  StreamSubscription? _tracksSubscription;

  /// 当前播放的媒体绝对路径
  String? _currentMediaPath;

  /// 当前媒体的全部字幕轨道（空 = 无字幕）
  List<SubtitleTrack> _tracks = const [];

  /// 当前生效的字幕轨道（null = 关闭；打开文件后与 mpv `sid` 同步）
  SubtitleTrack? _primary;

  /// 当前视频已导入的外挂字幕绝对路径（按视频独立隔离）
  final List<String> _externalPaths = [];

  /// 选中外挂字幕的源路径（按路径恢复勾选，见 [_resolveSelectionBySource]）
  String? _primarySourcePath;

  /// 最近一次 reapply 对应的媒体（防横竖屏页重复应用 / 切集重复添加）
  String? _appliedMedia;

  /// 轨道读取是否进行中（防并发刷新互相覆盖）
  bool _loading = false;

  /// 最近一次 fetchTracks 检测到被 mpv 选中的轨道 ID
  String? _lastSelectedTrackId;

  List<SubtitleTrack> get tracks => List.unmodifiable(_tracks);
  SubtitleTrack? get primary => _primary;
  String? get primarySourcePath => _primarySourcePath;
  List<String> get externalPaths => List.unmodifiable(_externalPaths);

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// 读取当前媒体的字幕轨道列表（仅 subtitle 类型；'no' 等伪轨排除）。
  Future<List<SubtitleTrack>> fetchTracks() async {
    final native = _native;
    if (native == null) return const [];
    final countStr = await native.getProperty('track-list/count');
    final count = int.tryParse(countStr) ?? 0;
    if (count <= 0) return const [];
    final result = <SubtitleTrack>[];
    String? selectedSubId;
    for (var i = 0; i < count; i++) {
      final type = await native.getProperty('track-list/$i/type');
      if (type != 'sub') continue;
      final id = await native.getProperty('track-list/$i/id');
      if (id.isEmpty || id == 'no') continue;
      final title = await native.getProperty('track-list/$i/title');
      final lang = await native.getProperty('track-list/$i/lang');
      final codec = await native.getProperty('track-list/$i/codec');
      final external = await native.getProperty('track-list/$i/external');
      final selected = await native.getProperty('track-list/$i/selected');
      final sourcePath =
          await native.getProperty('track-list/$i/external-filename');
      if (selected == 'yes') {
        selectedSubId = id;
      }
      result.add(
        SubtitleTrack(
          id: id,
          title: title.isEmpty ? null : title,
          language: lang.isEmpty ? null : lang,
          codec: codec.isEmpty ? null : codec,
          external: external == 'yes',
          sourcePath: sourcePath.isEmpty ? null : sourcePath,
        ),
      );
    }
    _lastSelectedTrackId = selectedSubId;
    return result;
  }

  /// mpv 当前生效的 `sid`（可能为 'no' / 'auto' / 轨道 id）
  Future<String> _readActiveSid() async {
    final native = _native;
    if (native == null) return 'no';
    try {
      final sid = (await native.getProperty('sid')).trim();
      return sid.isEmpty ? 'no' : sid;
    } catch (_) {
      return 'no';
    }
  }

  /// 用 mpv 实际生效的 sid 同步 [primary]（打开/重开后 mpv 自动选的轨道
  /// 也要反映到 UI 选中态 + 内嵌样式策略）。
  Future<void> _syncActiveFromMpv() async {
    final sid = await _readActiveSid();
    SubtitleTrack? resolved;
    if (sid != 'no' && sid.isNotEmpty) {
      resolved = _resolveSelection(sid);
    }
    if (resolved == null && sid != 'no' && _lastSelectedTrackId != null) {
      resolved = _resolveSelection(_lastSelectedTrackId);
    }
    _primary = resolved;
    _primarySourcePath = resolved?.sourcePath;
    notifyListeners();
  }

  /// 重新加载轨道列表并同步当前选中（以 mpv 实际 sid 为准）。
  Future<void> reload() async {
    if (_loading) return;
    _loading = true;
    try {
      List<SubtitleTrack> tracks;
      try {
        tracks = await fetchTracks();
      } catch (_) {
        tracks = const [];
      }
      _tracks = tracks;
      await _syncActiveFromMpv();
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  /// 按 id 在现轨道中找回选中项（找不到返回 null = 已失效）
  SubtitleTrack? _resolveSelection(String? id) {
    if (id == null || id == 'no' || id == 'auto') return null;
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 按源路径在现轨道中找回外挂字幕（切集重新 sub-add 后 id 变化，路径稳定）
  SubtitleTrack? _resolveSelectionBySource(String? sourcePath) {
    if (sourcePath == null) return null;
    for (final t in _tracks) {
      if (t.external && t.sourcePath == sourcePath) return t;
    }
    return null;
  }

  /// 勾选字幕轨道：传 null 关闭。单选模型——同一时刻只允许一条轨道生效。
  Future<void> selectTrack(SubtitleTrack? track) async {
    final native = _native;
    if (native == null) return;
    try {
      await native.setProperty('sid', track?.id ?? 'no');
    } catch (_) {
      return;
    }
    _primary = track;
    _primarySourcePath = track?.sourcePath;
    if (_currentMediaPath != null) {
      await _settings.setSelectedSubtitleFor(
        _currentMediaPath!,
        track?.sourcePath ?? track?.id ?? 'no',
      );
    }
    await _applyStyleForCurrent();
    notifyListeners();
  }

  /// 面板点击轨道的两态循环：选中 → 关闭；未选中 → 选中。
  Future<void> cycleSelection(SubtitleTrack track) async {
    if (_primary?.id == track.id) {
      await selectTrack(null);
    } else {
      await selectTrack(track);
    }
  }

  /// 导入外挂字幕：原生侧先把 content:// 拷贝为真实路径（若需要），
  /// 再 `sub-add <path> select` 并刷新轨道列表；成功后记忆路径（绑定当前视频）。
  Future<bool> addExternalSubtitle(String subtitlePath) async {
    final native = _native;
    if (native == null || subtitlePath.isEmpty) return false;
    try {
      await native.command(['sub-add', subtitlePath, 'select']);
    } catch (_) {
      return false;
    }
    if (!_externalPaths.contains(subtitlePath)) {
      _externalPaths.add(subtitlePath);
    }
    if (_currentMediaPath != null) {
      await _settings.addImportedSubtitleFor(_currentMediaPath!, subtitlePath);
      await _settings.setSelectedSubtitleFor(_currentMediaPath!, subtitlePath);
    }
    await reload();
    notifyListeners();
    return true;
  }

  /// 移除已导入的外挂字幕：`sub-remove` + 从当前视频记忆列表删除。
  Future<void> removeExternalSubtitle(SubtitleTrack track) async {
    final native = _native;
    if (native == null || track.id.isEmpty) return;
    try {
      await native.command(['sub-remove', track.id]);
    } catch (_) {}
    final source = track.sourcePath;
    if (source != null) {
      _externalPaths.remove(source);
      if (_currentMediaPath != null) {
        await _settings.removeImportedSubtitleFor(_currentMediaPath!, source);
      }
    }
    _primarySourcePath = null;
    await reload();
    notifyListeners();
  }

  /// 打开媒体 / 切集后调用（由播放页在 open 完成后触发）：
  /// - 按媒体路径独立加载该视频专属的外挂字幕；
  /// - 恢复该视频最后一次选中的字幕轨道；
  /// - 应用全部字幕设置。
  Future<void> reapplyForMedia(String mediaPath) async {
    if (_appliedMedia == mediaPath) return;
    _appliedMedia = mediaPath;
    _currentMediaPath = mediaPath;
    final native = _native;
    if (native == null) return;

    // 获取当前视频专属导入的外挂字幕
    final videoSubs = _settings.getImportedSubtitlesFor(mediaPath);
    _externalPaths.clear();
    _externalPaths.addAll(videoSubs);

    // 挂载属于当前视频的外挂字幕
    for (final path in _externalPaths) {
      try {
        await native.command(['sub-add', path, 'auto']);
      } catch (_) {}
    }
    await reload();

    // 恢复该视频最后一次选中的字幕
    final savedSub = _settings.getSelectedSubtitleFor(mediaPath);
    if (savedSub == 'no') {
      try {
        await native.setProperty('sid', 'no');
      } catch (_) {}
      _primary = null;
      _primarySourcePath = null;
    } else if (savedSub != null && savedSub.isNotEmpty) {
      final t = _resolveSelectionBySource(savedSub) ?? _resolveSelection(savedSub);
      if (t != null) {
        try {
          await native.setProperty('sid', t.id);
        } catch (_) {}
        _primary = t;
        _primarySourcePath = t.sourcePath;
      }
    }

    await _syncActiveFromMpv();
    await applyAllSettings();
  }

  /// 切集前清空状态（与 ChapterTracker.clear 同思路，防旧媒体数据闪现）
  void clear() {
    _tracks = const [];
    _primary = null;
    _primarySourcePath = null;
    _externalPaths.clear();
    notifyListeners();
  }

  /// 应用全部字幕设置（延迟/大小/颜色/描边/阴影/背景/粗细/斜体/间距/模糊/
  /// 位置/字体/内嵌样式策略）。
  Future<void> applyAllSettings() async {
    final native = _native;
    if (native == null) return;
    final s = _settings;
    try {
      await native.setProperty('sub-delay', _fmtDouble(s.delay));
      await native.setProperty('sub-scale', _fmtDouble(s.scale));
      await native.setProperty('sub-pos', _fmtDouble(s.position));
      await native.setProperty('sub-color', s.color);
      // 描边
      await native.setProperty('sub-border-style', s.borderStyle.mpvValue);
      await native.setProperty('sub-border-size', _fmtDouble(s.borderSize));
      await native.setProperty('sub-border-color', s.borderColor ?? '#000000');
      // 阴影
      await native.setProperty('sub-shadow-offset', _fmtDouble(s.shadowOffset));
      await native.setProperty('sub-shadow-color', s.shadowColor ?? '#00000000');
      // 背景
      await native.setProperty('sub-back-color', s.backColor ?? '#00000000');
      // 粗细 / 斜体 / 字间距 / 模糊
      await native.setProperty('sub-bold', s.bold ? 'yes' : 'no');
      await native.setProperty('sub-italic', s.italic ? 'yes' : 'no');
      await native.setProperty('sub-spacing', _fmtDouble(s.spacing));
      await native.setProperty('sub-blur', _fmtDouble(s.blur));
      // 字体设置（路线 C：默认直通系统字库 /system/fonts，零 APK 开销，100% 稳定）
      await native.setProperty('sub-font-provider', 'auto');
      await native.setProperty('embeddedfonts', 'yes');
      await native.setProperty('sub-fonts-dir', '/system/fonts');
      await native.setProperty('sub-font', kDefaultFontName);
      await _applyStyleForCurrent();
    } catch (_) {
      // 播放器不可用（已销毁）时静默
    }
  }

  /// 内嵌样式策略：
  /// - 开启「强制覆盖内嵌样式」→ `force`（用户样式生效，强制覆盖 ASS 样式与字体）；
  /// - 未开启「强制覆盖内嵌样式」→ `scale`（默认：mpv 完美保留 ASS 原生字体、特效、位置和排版，同时响应缩放调节）。
  /// - 普通文本字幕（SRT/VTT）在 scale 和 force 模式下均能正常响应用户样式。
  Future<void> _applyStyleForCurrent() async {
    final native = _native;
    if (native == null) return;
    final value = _settings.overrideEmbeddedStyle ? 'force' : 'scale';
    try {
      await native.setProperty('sub-ass-override', value);
      await native.setProperty('sub-font-provider', 'auto');
      await native.command(['sub-reload']);
    } catch (_) {}
  }

  /// 播放器初始就绪时应用一次设置（初始化越早越好，避免首帧无字幕样式）
  Future<void> applyOnInit() async {
    await _settings.ensureLoaded();
    await DeviceServices.ensureDefaultFontCopied();
    await applyAllSettings();
  }

  static String _fmtDouble(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _tracksSubscription?.cancel();
    _tracks = const [];
    _primary = null;
    super.dispose();
  }
}