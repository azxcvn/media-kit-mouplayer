import 'package:flutter/material.dart' show FontWeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/app_font_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 全局字体设置服务测试（工作.md 第 3 点）：
/// 默认值、开关/字体/缩放/字重持久化、effective 生效条件、钳制。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppFontSettings.instance.resetForTest();
  });

  final s = AppFontSettings.instance;

  test('默认值：未启用 / 无字体 / 缩放 1.0 / 字重默认(-1)', () {
    expect(s.enabled, isFalse);
    expect(s.family, isNull);
    expect(s.file, isNull);
    expect(s.textScale, 1.0);
    expect(s.fontWeightIndex, -1);
    expect(s.effectiveFamily, isNull);
    expect(s.effectiveFontWeight, isNull);
    expect(s.effectiveTextScale, 1.0);
  });

  test('开关 / 字体 / 缩放 / 字重持久化（模拟重启 load）', () async {
    await s.setEnabled(true);
    await s.setFont('MyFont', 'myfont.ttf');
    await s.setTextScale(1.2);
    await s.setFontWeightIndex(6);
    await s.load();
    expect(s.enabled, isTrue);
    expect(s.family, 'MyFont');
    expect(s.file, 'myfont.ttf');
    expect(s.textScale, 1.2);
    expect(s.fontWeightIndex, 6);
  });

  test('缩放 / 字重钳制到范围', () async {
    await s.setTextScale(9);
    expect(s.textScale, AppFontSettings.maxTextScale);
    await s.setTextScale(0.1);
    expect(s.textScale, AppFontSettings.minTextScale);
    await s.setFontWeightIndex(99);
    expect(s.fontWeightIndex, 8);
    await s.setFontWeightIndex(-99);
    expect(s.fontWeightIndex, -1);
  });

  test('effective 生效条件：开关关闭时不生效（family 已选仍跟随系统）', () async {
    await s.setFont('MyFont', 'myfont.ttf');
    await s.setFontWeightIndex(4);
    // 开关未开：family 已选但未启用 → 全部回落默认
    expect(s.effectiveFamily, isNull);
    expect(s.effectiveFontWeight, isNull);
    expect(s.effectiveTextScale, 1.0);
    await s.setEnabled(true);
    expect(s.effectiveFamily, 'MyFont');
    expect(s.effectiveFontWeight, FontWeight.w500);
    expect(s.effectiveTextScale, 1.0);
    await s.setTextScale(1.3);
    expect(s.effectiveTextScale, 1.3);
  });

  test('设置变更触发通知（ListenableBuilder 刷新依据）', () async {
    await s.ensureLoaded();
    var notified = 0;
    void listener() => notified++;
    s.addListener(listener);
    await s.setEnabled(true);
    await s.setEnabled(true); // 同值不重复通知
    s.removeListener(listener);
    expect(notified, 1);
  });
}
