import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_font_mode.dart';
import 'package:moumou/services/danmaku_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕设置服务测试（阶段2）：默认值、钳制、持久化恢复、一键恢复默认。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DanmakuSettings.instance.resetForTest();
  });

  final s = DanmakuSettings.instance;

  test('默认值：字号16 / 字重4 / 速度10s / 不透明1.0 / 描边1.5 / 全部显示', () {
    expect(s.fontSize, 16);
    expect(s.fontWeight, 4);
    expect(s.scrollSeconds, 10);
    expect(s.opacity, 1.0);
    expect(s.strokeWidth, 1.5);
    expect(s.randomColor, isFalse);
    expect(s.area, 1.0);
    expect(s.lineHeight, 1.6);
    expect(s.showTop, isTrue);
    expect(s.showBottom, isTrue);
    expect(s.showScroll, isTrue);
    expect(s.massiveMode, isFalse);
    expect(s.deduplication, isFalse);
    expect(s.timeOffsetSeconds, 0);
  });

  test('样式 setter 持久化（模拟重启 load）', () async {
    await s.setFontSize(24);
    await s.setFontWeight(7);
    await s.setScrollSeconds(6);
    await s.setOpacity(0.5);
    await s.setStrokeWidth(0);
    await s.setRandomColor(true);
    await s.load();
    expect(s.fontSize, 24);
    expect(s.fontWeight, 7);
    expect(s.scrollSeconds, 6);
    expect(s.opacity, 0.5);
    expect(s.strokeWidth, 0);
    expect(s.randomColor, isTrue);
  });

  test('配置 setter 持久化（模拟重启 load）', () async {
    await s.setArea(0.5);
    await s.setLineHeight(2.0);
    await s.setShowTop(false);
    await s.setShowBottom(false);
    await s.setShowScroll(false);
    await s.setMassiveMode(true);
    await s.setDeduplication(true);
    await s.load();
    expect(s.area, 0.5);
    expect(s.lineHeight, 2.0);
    expect(s.showTop, isFalse);
    expect(s.showBottom, isFalse);
    expect(s.showScroll, isFalse);
    expect(s.massiveMode, isTrue);
    expect(s.deduplication, isTrue);
  });

  test('字号/速度/不透明度/描边钳制到滑杆范围', () async {
    await s.setFontSize(999);
    expect(s.fontSize, DanmakuSettings.maxFontSize);
    await s.setFontSize(1);
    expect(s.fontSize, DanmakuSettings.minFontSize);
    await s.setScrollSeconds(0.1);
    expect(s.scrollSeconds, DanmakuSettings.minScrollSeconds);
    await s.setScrollSeconds(100);
    expect(s.scrollSeconds, DanmakuSettings.maxScrollSeconds);
    await s.setOpacity(0.01);
    expect(s.opacity, DanmakuSettings.minOpacity);
    await s.setStrokeWidth(50);
    expect(s.strokeWidth, DanmakuSettings.maxStrokeWidth);
  });

  test('区域/行高钳制；字重钳到 0–8', () async {
    await s.setArea(5);
    expect(s.area, DanmakuSettings.maxArea);
    await s.setArea(0.01);
    expect(s.area, DanmakuSettings.minArea);
    await s.setLineHeight(9);
    expect(s.lineHeight, DanmakuSettings.maxLineHeight);
    await s.setFontWeight(99);
    expect(s.fontWeight, 8);
    await s.setFontWeight(-1);
    expect(s.fontWeight, 0);
  });

  test('load 时越界历史值收窄', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('danmaku_font_size', 999);
    await prefs.setDouble('danmaku_speed', 0.1);
    await s.load();
    expect(s.fontSize, DanmakuSettings.maxFontSize);
    expect(s.scrollSeconds, DanmakuSettings.minScrollSeconds);
  });

  test('恢复默认：全部回默认值且持久化', () async {
    await s.setFontSize(30);
    await s.setRandomColor(true);
    await s.setShowTop(false);
    await s.setMassiveMode(true);
    await s.setTimeOffset(60);
    await s.reset();
    expect(s.fontSize, 16);
    expect(s.randomColor, isFalse);
    expect(s.showTop, isTrue);
    expect(s.massiveMode, isFalse);
    expect(s.timeOffsetSeconds, 0);
    // 持久化确认：重载后仍是默认值
    await s.load();
    expect(s.fontSize, 16);
    expect(s.randomColor, isFalse);
    expect(s.timeOffsetSeconds, 0);
  });

  test('时间轴偏移：取整 / 持久化 / 钳制', () async {
    expect(s.timeOffsetSeconds, 0);
    await s.setTimeOffset(45.6); // 取整到整数秒
    expect(s.timeOffsetSeconds, 46);
    await s.load();
    expect(s.timeOffsetSeconds, 46);
    await s.setTimeOffset(999);
    expect(s.timeOffsetSeconds, DanmakuSettings.maxTimeOffsetSeconds);
    await s.setTimeOffset(-999);
    expect(s.timeOffsetSeconds, DanmakuSettings.minTimeOffsetSeconds);
  });

  test('设置变更触发通知（面板 ListenableBuilder 刷新依据）', () async {
    await s.ensureLoaded(); // 模拟 main.dart 启动加载已完成（load 的通知不计入）
    var notified = 0;
    void listener() => notified++;
    s.addListener(listener);
    await s.setFontSize(20);
    await s.setFontSize(20); // 同值不重复通知
    s.removeListener(listener);
    expect(notified, 1);
  });

  test('弹幕字体默认值：跟随系统 / 无自定义字体', () {
    expect(s.fontMode, DanmakuFontMode.followSystem);
    expect(s.customFontFamily, isNull);
    expect(s.customFontFile, isNull);
  });

  test('弹幕字体模式 / 自定义字体持久化（模拟重启 load）', () async {
    await s.setFontMode(DanmakuFontMode.custom);
    await s.setCustomFont('DmFont', 'dmfont.otf');
    await s.load();
    expect(s.fontMode, DanmakuFontMode.custom);
    expect(s.customFontFamily, 'DmFont');
    expect(s.customFontFile, 'dmfont.otf');
  });

  test('恢复默认：弹幕字体回跟随系统且清自定义字体', () async {
    await s.setFontMode(DanmakuFontMode.followApp);
    await s.setCustomFont('DmFont', 'dmfont.otf');
    await s.reset();
    expect(s.fontMode, DanmakuFontMode.followSystem);
    expect(s.customFontFamily, isNull);
    expect(s.customFontFile, isNull);
    // 持久化确认
    await s.load();
    expect(s.fontMode, DanmakuFontMode.followSystem);
    expect(s.customFontFamily, isNull);
    expect(s.customFontFile, isNull);
  });
}
