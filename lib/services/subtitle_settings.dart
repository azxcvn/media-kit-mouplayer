import 'package:flutter/foundation.dart';
import 'package:moumou/models/subtitle_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字幕设置（工作.md 阶段1 第 3 点）：字幕延迟 / 样式 / 杂项 / 字体的全局设置。
///
/// 全局单例（同 [PlayerControlsSettings] 模式），ChangeNotifier + shared_preferences
/// 持久化；字幕面板与播放页共同监听。设置值直接映射 mpv 属性：
/// - 延迟 → `sub-delay`（秒）；
/// - 样式 → `sub-scale`（大小）、`sub-color`（文字色）、`sub-border-color`/`sub-border-size`
///   （描边）、`sub-shadow-color`/`sub-shadow-offset`（阴影）、`sub-back-color`（背景）、
///   `sub-bold`/`sub-italic`（粗细/斜体）、`sub-spacing`（字间距）、`sub-blur`（模糊）、
///   `sub-ass-override`（是否强制覆盖内嵌样式，默认关闭 = 尊重内嵌样式）；
/// - 杂项 → `sub-pos`（垂直位置）、`sub-align-x`（水平对齐）、`sub-margin-x`/`sub-margin-y`（边距）；
/// - 字体 → `sub-font`（'auto' 或自导入字体路径）+ `sub-fonts-dir`。
class SubtitleSettings extends ChangeNotifier {
  static final SubtitleSettings instance = SubtitleSettings._();

  SubtitleSettings._();

  /// 加载去重（与 PlayerControlsSettings.ensureLoaded 同模式）
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyDelay = 'subtitle_settings_delay';
  static const _keyScale = 'subtitle_settings_scale';
  static const _keyPos = 'subtitle_settings_pos';
  static const _keyAlign = 'subtitle_settings_align';
  static const _keyColor = 'subtitle_settings_color';
  static const _keyFont = 'subtitle_settings_font';
  static const _keyOverride = 'subtitle_settings_override';
  static const _keyBorderColor = 'subtitle_settings_border_color';
  static const _keyBorderSize = 'subtitle_settings_border_size';
  static const _keyShadowColor = 'subtitle_settings_shadow_color';
  static const _keyShadowOffset = 'subtitle_settings_shadow_offset';
  static const _keyBackColor = 'subtitle_settings_back_color';
  static const _keyBold = 'subtitle_settings_bold';
  static const _keyItalic = 'subtitle_settings_italic';
  static const _keySpacing = 'subtitle_settings_spacing';
  static const _keyBlur = 'subtitle_settings_blur';
  static const _keyMarginX = 'subtitle_settings_margin_x';
  static const _keyMarginY = 'subtitle_settings_margin_y';
  static const _keyImportedFonts = 'subtitle_settings_imported_fonts';
  static const _keyBorderStyle = 'subtitle_settings_border_style';
  static const _keyImportedSubtitles = 'subtitle_settings_imported_subtitles';

  /// 字幕延迟范围：-60 – +60 秒（工作.md 阶段1 第 3 点）
  static const double minDelay = -60;
  static const double maxDelay = 60;

  /// 字幕大小范围（mpv sub-scale）
  static const double minScale = 0.5;
  static const double maxScale = 3.0;

  /// 垂直位置范围（mpv sub-pos，100 = 屏幕底部）
  static const double minPos = 0;
  static const double maxPos = 100;

  /// 描边/阴影/间距等 0 – 20 的通用上限
  static const double maxStyleValue = 20;

  double _delay = 0;
  double _scale = 1.0;
  double _position = 100;
  SubtitleAlign _align = SubtitleAlign.center;
  String _color = '#FFFFFF';
  String _font = 'auto';
  bool _overrideEmbeddedStyle = false;

  // 扩展样式（工作.md 阶段1 第 3 点：补全小喵 player 的字幕样式项）
  String? _borderColor; // 描边颜色（null = 默认黑）
  double _borderSize = 2.5; // 描边粗细
  String? _shadowColor; // 阴影颜色
  double _shadowOffset = 0; // 阴影偏移（0 = 无阴影）
  String? _backColor; // 背景色（null = 透明）
  bool _bold = false;
  bool _italic = false;
  double _spacing = 0;
  double _blur = 0;
  double _marginX = 0;
  double _marginY = 0;
  SubtitleBorderStyle _borderStyle = SubtitleBorderStyle.none;

  /// 已导入的字体文件路径列表（用户自导入，见 [importFont]）
  List<String> _importedFonts = [];

  /// 已导入的外挂字幕绝对路径列表（跨播放会话持久化，
  /// 见 [SubtitleController.addExternalSubtitle]）
  List<String> _importedSubtitlePaths = [];

  double get delay => _delay;
  double get scale => _scale;
  double get position => _position;
  SubtitleAlign get align => _align;
  String get color => _color;
  String get font => _font;
  bool get overrideEmbeddedStyle => _overrideEmbeddedStyle;

  String? get borderColor => _borderColor;
  double get borderSize => _borderSize;
  String? get shadowColor => _shadowColor;
  double get shadowOffset => _shadowOffset;
  String? get backColor => _backColor;
  bool get bold => _bold;
  bool get italic => _italic;
  double get spacing => _spacing;
  double get blur => _blur;
  double get marginX => _marginX;
  double get marginY => _marginY;
  SubtitleBorderStyle get borderStyle => _borderStyle;
  List<String> get importedFonts => List.unmodifiable(_importedFonts);
  List<String> get importedSubtitlePaths =>
      List.unmodifiable(_importedSubtitlePaths);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _delay = (prefs.getDouble(_keyDelay) ?? 0).clamp(minDelay, maxDelay);
    _scale = (prefs.getDouble(_keyScale) ?? 1.0).clamp(minScale, maxScale);
    _position = (prefs.getDouble(_keyPos) ?? 100).clamp(minPos, maxPos);
    _align = SubtitleAlign.byMpvValue(prefs.getString(_keyAlign) ?? 'center');
    _color = prefs.getString(_keyColor) ?? '#FFFFFF';
    _font = prefs.getString(_keyFont) ?? 'auto';
    _overrideEmbeddedStyle = prefs.getBool(_keyOverride) ?? false;
    _borderColor = prefs.getString(_keyBorderColor);
    _borderSize = (prefs.getDouble(_keyBorderSize) ?? 2.5)
        .clamp(0, maxStyleValue);
    _shadowColor = prefs.getString(_keyShadowColor);
    _shadowOffset =
        (prefs.getDouble(_keyShadowOffset) ?? 0).clamp(0, maxStyleValue);
    _backColor = prefs.getString(_keyBackColor);
    _bold = prefs.getBool(_keyBold) ?? false;
    _italic = prefs.getBool(_keyItalic) ?? false;
    _spacing = (prefs.getDouble(_keySpacing) ?? 0).clamp(0, maxStyleValue);
    _blur = (prefs.getDouble(_keyBlur) ?? 0).clamp(0, maxStyleValue);
    _marginX = (prefs.getDouble(_keyMarginX) ?? 0).clamp(0, 100);
    _marginY = (prefs.getDouble(_keyMarginY) ?? 0).clamp(0, 100);
    _borderStyle =
        SubtitleBorderStyle.byMpvValue(prefs.getString(_keyBorderStyle) ?? 'flat');
    _importedFonts = prefs.getStringList(_keyImportedFonts) ?? [];
    _importedSubtitlePaths = prefs.getStringList(_keyImportedSubtitles) ?? [];
    notifyListeners();
  }

  // ── 延迟 ──────────────────────────────────────────────

  Future<void> setDelay(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minDelay, maxDelay);
    if ((_delay - clamped).abs() < 0.001) return;
    _delay = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDelay, clamped);
  }

  Future<void> adjustDelay(double delta) => setDelay(_delay + delta);

  // ── 样式 ──────────────────────────────────────────────

  Future<void> setScale(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minScale, maxScale);
    if ((_scale - clamped).abs() < 0.001) return;
    _scale = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyScale, clamped);
  }

  Future<void> setColor(String hex) async {
    await ensureLoaded();
    if (_color == hex) return;
    _color = hex;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyColor, hex);
  }

  Future<void> setBorderColor(String? hex) async {
    await ensureLoaded();
    if (_borderColor == hex) return;
    _borderColor = hex;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (hex == null) {
      await prefs.remove(_keyBorderColor);
    } else {
      await prefs.setString(_keyBorderColor, hex);
    }
  }

  Future<void> setBorderSize(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, maxStyleValue).toDouble();
    if ((_borderSize - clamped).abs() < 0.001) return;
    _borderSize = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBorderSize, clamped);
  }

  Future<void> setShadowColor(String? hex) async {
    await ensureLoaded();
    if (_shadowColor == hex) return;
    _shadowColor = hex;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (hex == null) {
      await prefs.remove(_keyShadowColor);
    } else {
      await prefs.setString(_keyShadowColor, hex);
    }
  }

  Future<void> setShadowOffset(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, maxStyleValue).toDouble();
    if ((_shadowOffset - clamped).abs() < 0.001) return;
    _shadowOffset = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyShadowOffset, clamped);
  }

  Future<void> setBorderStyle(SubtitleBorderStyle v) async {
    await ensureLoaded();
    if (_borderStyle == v) return;
    _borderStyle = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBorderStyle, v.mpvValue);
  }

  Future<void> setBackColor(String? hex) async {
    await ensureLoaded();
    if (_backColor == hex) return;
    _backColor = hex;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (hex == null) {
      await prefs.remove(_keyBackColor);
    } else {
      await prefs.setString(_keyBackColor, hex);
    }
  }

  Future<void> setBold(bool v) async {
    await ensureLoaded();
    if (_bold == v) return;
    _bold = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBold, v);
  }

  Future<void> setItalic(bool v) async {
    await ensureLoaded();
    if (_italic == v) return;
    _italic = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyItalic, v);
  }

  Future<void> setSpacing(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, maxStyleValue).toDouble();
    if ((_spacing - clamped).abs() < 0.001) return;
    _spacing = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySpacing, clamped);
  }

  Future<void> setBlur(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, maxStyleValue).toDouble();
    if ((_blur - clamped).abs() < 0.001) return;
    _blur = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBlur, clamped);
  }

  Future<void> setOverrideEmbeddedStyle(bool v) async {
    await ensureLoaded();
    if (_overrideEmbeddedStyle == v) return;
    _overrideEmbeddedStyle = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOverride, v);
  }

  // ── 杂项 ──────────────────────────────────────────────

  Future<void> setPosition(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(minPos, maxPos);
    if ((_position - clamped).abs() < 0.001) return;
    _position = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPos, clamped);
  }

  Future<void> setAlign(SubtitleAlign v) async {
    await ensureLoaded();
    if (_align == v) return;
    _align = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAlign, v.mpvValue);
  }

  Future<void> setMarginX(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, 100).toDouble();
    if ((_marginX - clamped).abs() < 0.001) return;
    _marginX = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMarginX, clamped);
  }

  Future<void> setMarginY(double v) async {
    await ensureLoaded();
    final clamped = v.clamp(0, 100).toDouble();
    if ((_marginY - clamped).abs() < 0.001) return;
    _marginY = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMarginY, clamped);
  }

  // ── 字体 ──────────────────────────────────────────────

  /// 字体（'auto' = 跟随 mpv 默认；否则为自导入字体文件路径）
  Future<void> setFont(String font) async {
    await ensureLoaded();
    if (_font == font) return;
    _font = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFont, font);
  }

  /// 导入一个字体文件路径：去重加入列表并选中。
  Future<void> importFont(String path) async {
    await ensureLoaded();
    if (!_importedFonts.contains(path)) {
      _importedFonts = [..._importedFonts, path];
    }
    _font = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyImportedFonts, _importedFonts);
    await prefs.setString(_keyFont, path);
  }

  /// 移除一个已导入字体；若正被选中则回到「跟随默认」。
  Future<void> removeFont(String path) async {
    await ensureLoaded();
    _importedFonts = _importedFonts.where((f) => f != path).toList();
    if (_font == path) _font = 'auto';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyImportedFonts, _importedFonts);
    await prefs.setString(_keyFont, _font);
  }

  // ── 外挂字幕记忆 ──────────────────────────────────────

  /// 记忆一条导入的外挂字幕路径（跨播放会话；见 [SubtitleController]）。
  Future<void> addImportedSubtitle(String path) async {
    await ensureLoaded();
    if (_importedSubtitlePaths.contains(path)) return;
    _importedSubtitlePaths = [..._importedSubtitlePaths, path];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyImportedSubtitles, _importedSubtitlePaths);
  }

  /// 忘记一条已导入的外挂字幕路径。
  Future<void> removeImportedSubtitle(String path) async {
    await ensureLoaded();
    _importedSubtitlePaths =
        _importedSubtitlePaths.where((p) => p != path).toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyImportedSubtitles, _importedSubtitlePaths);
  }

  // ── 重置 ──────────────────────────────────────────────

  /// 重置所有字幕「样式」（文字颜色/描边/阴影/背景/粗细/斜体/间距/模糊/
  /// 描边模式/内嵌样式覆盖），保留 延迟/缩放/位置/字体 不重置。
  Future<void> resetStyles() async {
    await ensureLoaded();
    const clamp0 = 0.0;
    _color = '#FFFFFF';
    _borderColor = null;
    _borderSize = 2.5;
    _borderStyle = SubtitleBorderStyle.none;
    _shadowColor = null;
    _shadowOffset = 0;
    _backColor = null;
    _bold = false;
    _italic = false;
    _spacing = clamp0;
    _blur = clamp0;
    _overrideEmbeddedStyle = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyColor, _color);
    await prefs.remove(_keyBorderColor);
    await prefs.setDouble(_keyBorderSize, _borderSize);
    await prefs.setString(_keyBorderStyle, _borderStyle.mpvValue);
    await prefs.remove(_keyShadowColor);
    await prefs.setDouble(_keyShadowOffset, _shadowOffset);
    await prefs.remove(_keyBackColor);
    await prefs.setBool(_keyBold, _bold);
    await prefs.setBool(_keyItalic, _italic);
    await prefs.setDouble(_keySpacing, _spacing);
    await prefs.setDouble(_keyBlur, _blur);
    await prefs.setBool(_keyOverride, _overrideEmbeddedStyle);
  }

  /// 测试用：恢复默认值（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void reset() {
    _loadFuture = null;
    _delay = 0;
    _scale = 1.0;
    _position = 100;
    _align = SubtitleAlign.center;
    _color = '#FFFFFF';
    _font = 'auto';
    _overrideEmbeddedStyle = false;
    _borderColor = null;
    _borderSize = 2.5;
    _shadowColor = null;
    _shadowOffset = 0;
    _backColor = null;
    _bold = false;
    _italic = false;
    _spacing = 0;
    _blur = 0;
    _marginX = 0;
    _marginY = 0;
    _borderStyle = SubtitleBorderStyle.none;
    _importedFonts = [];
    _importedSubtitlePaths = [];
    notifyListeners();
  }
}
