import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:moumou/models/subtitle_track.dart';
import 'package:moumou/services/subtitle_settings.dart';

/// 字幕控制器：绑定单个播放器（横竖屏共享同一实例），
/// 维护「轨道列表 / 当前字幕轨道 / 外挂字幕路径」状态并直接驱动 mpv。
///
/// - **单选模型**（只允许同时启用一条字幕轨道，参考 mpv `sid`）；
/// - mpv 属性与命令（参考 mpvRx 的 SubtitleStyle / PlaybackSession）：
///   - 轨道列表：`track-list/count` + `track-list/$i/{type,id,title,lang,codec,external}`；
///   - 当前字幕：`sid`（id 或 'no'；打开文件后 mpv 会自动选一条轨道，
///     [reload] 会把 [primary] 同步成 mpv 实际生效的 sid，保证 UI 选中态
///     与内嵌样式策略（[SubtitleSettings.overrideEmbeddedStyle]）以真实轨道为准）；
///   - 外挂字幕：`sub-add <path> <flags>`（'select' = 立即选中；'auto' = 无字幕时才选，
///     重开文件恢复用），`sub-remove <id>` 移除；
///   - 设置：[SubtitleSettings] 各值映射 `sub-delay` / `sub-scale` / `sub-pos` /
///     `sub-color` / `sub-border-*` / `sub-back-color` / `sub-font` / `sub-ass-override`。
///
/// 内嵌样式策略：当前轨道为 ASS/SSA 且设置未开启「强制覆盖内嵌样式」时，
/// `sub-ass-override` 设为 `no`（启用字幕自带的样式与字体）；否则按用户样式渲染。
/// 打开视频的第一帧就生效（无需手动切换轨道）。
class SubtitleController extends ChangeNotifier {
  SubtitleController(this._player, {SubtitleSettings? settings})
      : _settings = settings ?? SubtitleSettings.instance {
    // 恢复「曾导入的外挂字幕」（跨播放会话持久化，见 SubtitleSettings）
    for (final p in _settings.importedSubtitlePaths) {
      if (!_externalPaths.contains(p)) _externalPaths.add(p);
    }
  }

  final Player _player;
  final SubtitleSettings _settings;

  /// 当前媒体的全部字幕轨道（空 = 无字幕）
  List<SubtitleTrack> _tracks = const [];

  /// 当前生效的字幕轨道（null = 关闭；打开文件后与 mpv `sid` 同步）
  SubtitleTrack? _primary;

  /// 已导入的外挂字幕绝对路径（跨会话记忆 + 切集/重开后重新 sub-add）
  final List<String> _externalPaths = [];

  /// 选中外挂字幕的源路径（按路径恢复勾选，见 [_resolveSelectionBySource]）
  String? _primarySourcePath;

  /// 最近一次 reapply 对应的媒体（防横竖屏页重复应用 / 切集重复添加）
  String? _appliedMedia;

  /// 轨道读取是否进行中（防并发刷新互相覆盖）
  bool _loading = false;

  List<SubtitleTrack> get tracks => List.unmodifiable(_tracks);
  SubtitleTrack? get primary => _primary;
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
    for (var i = 0; i < count; i++) {
      final type = await native.getProperty('track-list/$i/type');
      if (type != 'sub') continue;
      final id = await native.getProperty('track-list/$i/id');
      if (id.isEmpty || id == 'no') continue;
      final title = await native.getProperty('track-list/$i/title');
      final lang = await native.getProperty('track-list/$i/lang');
      final codec = await native.getProperty('track-list/$i/codec');
      final external = await native.getProperty('track-list/$i/external');
      final sourcePath =
          await native.getProperty('track-list/$i/external-filename');
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
    final resolved = _resolveSelection(sid);
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
  /// 再 `sub-add <path> select` 并刷新轨道列表；成功后记忆路径（跨会话持久化，
  /// 退出播放后再进来仍会恢复，见 [SubtitleSettings.addImportedSubtitle]）。
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
      await _settings.addImportedSubtitle(subtitlePath);
    }
    await reload();
    notifyListeners();
    return true;
  }

  /// 移除已导入的外挂字幕：`sub-remove` + 从记忆列表删除（持久化）。
  Future<void> removeExternalSubtitle(SubtitleTrack track) async {
    final native = _native;
    if (native == null || track.id.isEmpty) return;
    try {
      await native.command(['sub-remove', track.id]);
    } catch (_) {}
    final source = track.sourcePath;
    if (source != null && _externalPaths.remove(source)) {
      await _settings.removeImportedSubtitle(source);
    }
    _primarySourcePath = null;
    await reload();
    notifyListeners();
  }

  /// 打开媒体 / 切集后调用（由播放页在 open 完成后触发）：
  /// - 按媒体路径去重（横竖屏共享同一实例时只应用一次）；
  /// - 重新添加会话内/历史导入的外挂字幕（mpv 打开新媒体后外挂字幕被清空，
  ///   用 'auto' 标志避免抢占视频自带字幕的自动选择）；
  /// - 刷新轨道列表并恢复当前选中（外挂按源路径、内嵌按 id，尽力而为；
  ///   否则跟随 mpv 自动选择，保证内嵌样式策略以真实轨道为准）；
  /// - 应用全部字幕设置。
  Future<void> reapplyForMedia(String mediaPath) async {
    if (_appliedMedia == mediaPath) return;
    _appliedMedia = mediaPath;
    final native = _native;
    if (native == null) return;
    // 重新添加外挂字幕（打开新文件后原 track-list 已被清空）
    for (final path in _externalPaths) {
      try {
        await native.command(['sub-add', path, 'auto']);
      } catch (_) {}
    }
    await reload();
    // 尽力恢复上次选中：外挂按源路径（重新 sub-add 后 id 变化）；
    // 内嵌按原 id；都找不到则维持 mpv 的自动选择
    if (_primarySourcePath != null) {
      final t = _resolveSelectionBySource(_primarySourcePath);
      if (t != null) {
        try {
          await native.setProperty('sid', t.id);
        } catch (_) {}
      }
    } else if (_primary?.id != null) {
      final t = _resolveSelection(_primary!.id);
      if (t != null) {
        try {
          await native.setProperty('sid', t.id);
        } catch (_) {}
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
      if (s.borderColor != null) {
        await native.setProperty('sub-border-color', s.borderColor!);
      }
      // 阴影
      await native.setProperty('sub-shadow-offset', _fmtDouble(s.shadowOffset));
      if (s.shadowColor != null) {
        await native.setProperty('sub-shadow-color', s.shadowColor!);
      }
      // 背景
      if (s.backColor != null) {
        await native.setProperty('sub-back-color', s.backColor!);
      }
      // 粗细 / 斜体 / 字间距 / 模糊
      await native.setProperty('sub-bold', s.bold ? 'yes' : 'no');
      await native.setProperty('sub-italic', s.italic ? 'yes' : 'no');
      await native.setProperty('sub-spacing', _fmtDouble(s.spacing));
      await native.setProperty('sub-blur', _fmtDouble(s.blur));
      // 字体：'auto' 跟随默认；否则设字体目录 + 字体名（自导入）
      if (s.font != 'auto' && s.font.isNotEmpty) {
        final dir = _fontDirOf(s.font);
        if (dir != null && dir.isNotEmpty) {
          await native.setProperty('sub-fonts-dir', dir);
        }
        await native.setProperty('sub-font', _fontNameOf(s.font));
      }
      await _applyStyleForCurrent();
    } catch (_) {
      // 播放器不可用（已销毁）时静默
    }
  }

  /// 内嵌样式策略：当前轨道为 ASS/SSA 且未开启强制覆盖 → `no`
  /// （尊重字幕自带样式与字体）；否则 `force`（用户样式生效）。
  ///
  /// 以 [primary] 为准——打开文件后已与 mpv 实际 sid 同步，首帧即生效。
  Future<void> _applyStyleForCurrent() async {
    final native = _native;
    if (native == null) return;
    final styled = _primary?.isStyled ?? false;
    final value = (styled && !_settings.overrideEmbeddedStyle) ? 'no' : 'force';
    try {
      await native.setProperty('sub-ass-override', value);
      // 统一用 auto：既让内嵌字幕的嵌入字体可用，也能用回退字体渲染普通文本
      // （Android libass 拿不到系统字体，回退字体由 media_kit 经
      //  libassAndroidFont 拷入 sub-fonts-dir / sub-font，见 player_page）。
      await native.setProperty('sub-font-provider', 'auto');
    } catch (_) {}
  }

  /// 字体文件路径 → 字体名（去掉目录与扩展名，libass 按名称匹配）
  static String _fontNameOf(String path) {
    final segs = path.split('/');
    final name = segs.isEmpty ? path : segs.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 字体文件路径 → 所在目录（用于 mpv sub-fonts-dir）
  static String? _fontDirOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx <= 0 ? null : path.substring(0, idx);
  }

  /// 播放器初始就绪时应用一次设置（初始化越早越好，避免首帧无字幕样式）
  Future<void> applyOnInit() async {
    await _settings.ensureLoaded();
    await applyAllSettings();
  }

  static String _fmtDouble(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _tracks = const [];
    _primary = null;
    super.dispose();
  }
}