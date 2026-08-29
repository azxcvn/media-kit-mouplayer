/// 弹幕设置（阶段2，工作.md 弹幕第 4 点）：样式（字号/字重/速度/描边/
/// 不透明度/随机渐变色）+ 配置（显示区域/行高/三类弹幕显隐/海量弹幕/去重）。
///
/// 全局单例（同 [IntroOutroSettings] 模式）：ChangeNotifier +
/// shared_preferences 持久化——所有个性化设置跨重启视频/重启播放保留
/// （工作.md 弹幕第 6 点）。弹幕设置面板与 [DanmakuController] 共同监听：
/// 面板改值实时写盘 + 通知，控制器把设置映射到 canvas_danmaku 的
/// DanmakuOption（updateOption 热更新，见 danmaku_service.dart）。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DanmakuSettings extends ChangeNotifier {
  static final DanmakuSettings instance = DanmakuSettings._();

  DanmakuSettings._();

  /// 加载去重（risk_audit #9）：setter 在改设置前 await [ensureLoaded]，
  /// 防止启动时异步 load 尚未完成、用户已改设置被 load 覆盖
  Future<void>? _loadFuture;

  /// 确保已从磁盘加载完成（首次调用触发 load；并发调用共享同一 Future）
  Future<void> ensureLoaded() => _loadFuture ??= load();

  // ── 滑杆范围常量（面板滑杆与 load 钳制共用）──

  static const double minFontSize = 10;
  static const double maxFontSize = 30;
  static const double minFontWeight = 0; // FontWeight.values 下标
  static const double maxFontWeight = 8;
  static const double minScrollSeconds = 2; // 滚动耗时下限（最快）
  static const double maxScrollSeconds = 16;
  static const double minOpacity = 0.1;
  static const double maxOpacity = 1.0;
  static const double minStrokeWidth = 0;
  static const double maxStrokeWidth = 4;
  static const double minArea = 0.1;
  static const double maxArea = 1.0;
  static const double minLineHeight = 0.5;
  static const double maxLineHeight = 3.0;
  static const double minTimeOffsetSeconds = -180;
  static const double maxTimeOffsetSeconds = 180;

  // ── 弹幕样式 ──

  /// 弹幕字号（px，canvas DanmakuOption.fontSize，默认 16）
  double _fontSize = 16;

  /// 字体字重（FontWeight.values 下标 0–8，4 = w500 中等，canvas 同下标语义）
  int _fontWeight = 4;

  /// 滚动弹幕横穿屏幕的耗时（秒，默认 10；值越大越慢——面板以
  /// 「弹幕速度」呈现，速度滑杆即调此值）
  double _scrollSeconds = 10;

  /// 不透明度（0.1–1.0，默认 1.0）
  double _opacity = 1.0;

  /// 描边粗细（0–4，默认 1.5；0 = 无描边）
  double _strokeWidth = 1.5;

  /// 随机渐变色（默认关闭）：开启后忽略弹幕文件内颜色，所有弹幕按
  /// HSV 色轮渐变随机着色（算法见 utils/danmaku_random_color.dart）
  bool _randomColor = false;

  // ── 弹幕配置 ──

  /// 显示区域（0.1–1.0，屏幕高度比例，默认 1.0）
  double _area = 1.0;

  /// 行高（弹幕轨道行高倍数 0.5–3.0，默认 1.6）
  double _lineHeight = 1.6;

  /// 顶部弹幕显示（canvas hideTop 取反，默认显示）
  bool _showTop = true;

  /// 底部弹幕显示（canvas hideBottom 取反，默认显示）
  bool _showBottom = true;

  /// 滚动弹幕显示（canvas hideScroll 取反，默认显示）
  bool _showScroll = true;

  /// 海量弹幕（轨道占满时叠加绘制，默认关闭）
  bool _massiveMode = false;

  /// 弹幕去重（时间窗口内相同内容合并为一条，默认关闭；
  /// 算法见 utils/danmaku_dedup.dart）
  bool _deduplication = false;

  /// 时间轴偏移（秒，-180~180，默认 0；正 = 延后、负 = 提前）。
  /// 校准弹幕相对视频画面的显示时间（对齐 Kazumi danmakuTimeOffset）。
  double _timeOffset = 0;

  bool get randomColor => _randomColor;
  double get fontSize => _fontSize;
  int get fontWeight => _fontWeight;
  double get scrollSeconds => _scrollSeconds;
  double get opacity => _opacity;
  double get strokeWidth => _strokeWidth;
  double get area => _area;
  double get lineHeight => _lineHeight;
  bool get showTop => _showTop;
  bool get showBottom => _showBottom;
  bool get showScroll => _showScroll;
  bool get massiveMode => _massiveMode;
  bool get deduplication => _deduplication;
  double get timeOffsetSeconds => _timeOffset;

  /// 启动时加载（main.dart 调用）
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = (prefs.getDouble(_keyFontSize) ?? 16)
        .clamp(minFontSize, maxFontSize);
    _fontWeight =
        (prefs.getInt(_keyFontWeight) ?? 4).clamp(0, 8);
    _scrollSeconds = (prefs.getDouble(_keyScrollSeconds) ?? 10)
        .clamp(minScrollSeconds, maxScrollSeconds);
    _opacity =
        (prefs.getDouble(_keyOpacity) ?? 1.0).clamp(minOpacity, maxOpacity);
    _strokeWidth = (prefs.getDouble(_keyStrokeWidth) ?? 1.5)
        .clamp(minStrokeWidth, maxStrokeWidth);
    _randomColor = prefs.getBool(_keyRandomColor) ?? false;
    _area = (prefs.getDouble(_keyArea) ?? 1.0).clamp(minArea, maxArea);
    _lineHeight = (prefs.getDouble(_keyLineHeight) ?? 1.6)
        .clamp(minLineHeight, maxLineHeight);
    _showTop = prefs.getBool(_keyShowTop) ?? true;
    _showBottom = prefs.getBool(_keyShowBottom) ?? true;
    _showScroll = prefs.getBool(_keyShowScroll) ?? true;
    _massiveMode = prefs.getBool(_keyMassiveMode) ?? false;
    _deduplication = prefs.getBool(_keyDedup) ?? false;
    _timeOffset = (prefs.getDouble(_keyTimeOffset) ?? 0)
        .clamp(minTimeOffsetSeconds, maxTimeOffsetSeconds);
    notifyListeners();
  }

  // ── 样式 setter（改值 → notifyListeners → 异步写盘）──

  Future<void> setFontSize(double v) async {
    await ensureLoaded();
    final c = v.clamp(minFontSize, maxFontSize);
    if (_fontSize == c) return;
    _fontSize = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, c);
  }

  Future<void> setFontWeight(int v) async {
    await ensureLoaded();
    final c = v.clamp(minFontWeight.toInt(), maxFontWeight.toInt());
    if (_fontWeight == c) return;
    _fontWeight = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyFontWeight, c);
  }

  Future<void> setScrollSeconds(double v) async {
    await ensureLoaded();
    final c = v.clamp(minScrollSeconds, maxScrollSeconds);
    if (_scrollSeconds == c) return;
    _scrollSeconds = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyScrollSeconds, c);
  }

  Future<void> setOpacity(double v) async {
    await ensureLoaded();
    final c = v.clamp(minOpacity, maxOpacity);
    if (_opacity == c) return;
    _opacity = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyOpacity, c);
  }

  Future<void> setStrokeWidth(double v) async {
    await ensureLoaded();
    final c = v.clamp(minStrokeWidth, maxStrokeWidth);
    if (_strokeWidth == c) return;
    _strokeWidth = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStrokeWidth, c);
  }

  Future<void> setRandomColor(bool v) async {
    await ensureLoaded();
    if (_randomColor == v) return;
    _randomColor = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRandomColor, v);
  }

  // ── 配置 setter ──

  Future<void> setArea(double v) async {
    await ensureLoaded();
    final c = v.clamp(minArea, maxArea);
    if (_area == c) return;
    _area = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyArea, c);
  }

  Future<void> setLineHeight(double v) async {
    await ensureLoaded();
    final c = v.clamp(minLineHeight, maxLineHeight);
    if (_lineHeight == c) return;
    _lineHeight = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLineHeight, c);
  }

  Future<void> setShowTop(bool v) async {
    await ensureLoaded();
    if (_showTop == v) return;
    _showTop = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowTop, v);
  }

  Future<void> setShowBottom(bool v) async {
    await ensureLoaded();
    if (_showBottom == v) return;
    _showBottom = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowBottom, v);
  }

  Future<void> setShowScroll(bool v) async {
    await ensureLoaded();
    if (_showScroll == v) return;
    _showScroll = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowScroll, v);
  }

  Future<void> setMassiveMode(bool v) async {
    await ensureLoaded();
    if (_massiveMode == v) return;
    _massiveMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMassiveMode, v);
  }

  Future<void> setDeduplication(bool v) async {
    await ensureLoaded();
    if (_deduplication == v) return;
    _deduplication = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDedup, v);
  }

  Future<void> setTimeOffset(double v) async {
    await ensureLoaded();
    final c = v
        .roundToDouble()
        .clamp(minTimeOffsetSeconds, maxTimeOffsetSeconds);
    if (_timeOffset == c) return;
    _timeOffset = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTimeOffset, c);
  }

  // ── 一键恢复默认（保留在面板底部，设置值全部回默认）──

  /// 恢复默认设置：样式与配置全部回默认值
  Future<void> reset() async {
    await ensureLoaded();
    if (_isDefault) return;
    _fontSize = 16;
    _fontWeight = 4;
    _scrollSeconds = 10;
    _opacity = 1.0;
    _strokeWidth = 1.5;
    _randomColor = false;
    _area = 1.0;
    _lineHeight = 1.6;
    _showTop = true;
    _showBottom = true;
    _showScroll = true;
    _massiveMode = false;
    _deduplication = false;
    _timeOffset = 0;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, 16);
    await prefs.setInt(_keyFontWeight, 4);
    await prefs.setDouble(_keyScrollSeconds, 10);
    await prefs.setDouble(_keyOpacity, 1.0);
    await prefs.setDouble(_keyStrokeWidth, 1.5);
    await prefs.setBool(_keyRandomColor, false);
    await prefs.setDouble(_keyArea, 1.0);
    await prefs.setDouble(_keyLineHeight, 1.6);
    await prefs.setBool(_keyShowTop, true);
    await prefs.setBool(_keyShowBottom, true);
    await prefs.setBool(_keyShowScroll, true);
    await prefs.setBool(_keyMassiveMode, false);
    await prefs.setBool(_keyDedup, false);
    await prefs.setDouble(_keyTimeOffset, 0);
  }

  bool get _isDefault =>
      _fontSize == 16 &&
      _fontWeight == 4 &&
      _scrollSeconds == 10 &&
      _opacity == 1.0 &&
      _strokeWidth == 1.5 &&
      !_randomColor &&
      _area == 1.0 &&
      _lineHeight == 1.6 &&
      _showTop &&
      _showBottom &&
      _showScroll &&
      !_massiveMode &&
      !_deduplication &&
      _timeOffset == 0;

  // ── SharedPreferences 键 ──

  static const _keyFontSize = 'danmaku_font_size';
  static const _keyFontWeight = 'danmaku_font_weight';
  static const _keyScrollSeconds = 'danmaku_speed';
  static const _keyOpacity = 'danmaku_opacity';
  static const _keyStrokeWidth = 'danmaku_stroke_width';
  static const _keyRandomColor = 'danmaku_random_color';
  static const _keyArea = 'danmaku_area';
  static const _keyLineHeight = 'danmaku_line_height';
  static const _keyShowTop = 'danmaku_show_top';
  static const _keyShowBottom = 'danmaku_show_bottom';
  static const _keyShowScroll = 'danmaku_show_scroll';
  static const _keyMassiveMode = 'danmaku_massive_mode';
  static const _keyDedup = 'danmaku_dedup';
  static const _keyTimeOffset = 'danmaku_time_offset';

  /// 测试用：恢复默认值并清加载标记（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void resetForTest() {
    _loadFuture = null; // 下次 setter 重新触发 load（读当前 mock prefs）
    _fontSize = 16;
    _fontWeight = 4;
    _scrollSeconds = 10;
    _opacity = 1.0;
    _strokeWidth = 1.5;
    _randomColor = false;
    _area = 1.0;
    _lineHeight = 1.6;
    _showTop = true;
    _showBottom = true;
    _showScroll = true;
    _massiveMode = false;
    _deduplication = false;
    _timeOffset = 0;
    notifyListeners();
  }
}
