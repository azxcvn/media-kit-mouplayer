import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 片头片尾设置服务测试：默认值、钳制、范围收窄联动、一键重置与持久化。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IntroOutroSettings.instance.resetForTest();
  });

  final s = IntroOutroSettings.instance;

  test('默认值：关闭 / 片头片尾秒数 0 / 范围 180', () {
    expect(s.enabled, isFalse);
    expect(s.introSeconds, 0);
    expect(s.outroSeconds, 0);
    expect(s.introRange, IntroOutroSettings.defaultRangeSeconds);
    expect(s.outroRange, IntroOutroSettings.defaultRangeSeconds);
  });

  test('开关持久化（模拟重启 load）', () async {
    await s.setEnabled(true);
    await s.load();
    expect(s.enabled, isTrue);
  });

  test('片头秒数钳制到 0 – 当前范围', () async {
    await s.setIntroSeconds(120);
    expect(s.introSeconds, 120);
    await s.setIntroSeconds(9999);
    expect(s.introSeconds, 180); // 超范围 → 钳到范围上限
    await s.setIntroSeconds(-5);
    expect(s.introSeconds, 0); // 负数 → 0
  });

  test('片头范围钳制到 10 – 600；收窄时秒数同步收窄', () async {
    await s.setIntroSeconds(150);
    await s.setIntroRange(60);
    expect(s.introRange, 60);
    expect(s.introSeconds, 60); // 150 > 60 → 收窄
    await s.setIntroRange(5);
    expect(s.introRange, 10); // 钳到下限
    await s.setIntroRange(9999);
    expect(s.introRange, 600); // 钳到上限
  });

  test('片尾秒数/范围钳制同片头', () async {
    await s.setOutroSeconds(150);
    await s.setOutroRange(60);
    expect(s.outroSeconds, 60);
    expect(s.outroRange, 60);
    await s.setOutroSeconds(9999);
    expect(s.outroSeconds, 60);
  });

  test('一键重置：秒数清零、范围回默认、开关保持', () async {
    await s.setEnabled(true);
    await s.setIntroSeconds(90);
    await s.setOutroSeconds(45);
    await s.setIntroRange(300);
    await s.setOutroRange(500);
    await s.reset();
    expect(s.enabled, isTrue); // 开关保持不变（对齐 KT 实现）
    expect(s.introSeconds, 0);
    expect(s.outroSeconds, 0);
    expect(s.introRange, IntroOutroSettings.defaultRangeSeconds);
    expect(s.outroRange, IntroOutroSettings.defaultRangeSeconds);
  });

  test('持久化：全部字段 load 恢复（模拟重启）', () async {
    await s.setEnabled(true);
    await s.setIntroSeconds(75);
    await s.setOutroSeconds(20);
    await s.setIntroRange(240);
    await s.setOutroRange(360);
    await s.load();
    expect(s.enabled, isTrue);
    expect(s.introSeconds, 75);
    expect(s.outroSeconds, 20);
    expect(s.introRange, 240);
    expect(s.outroRange, 360);
  });

  test('load 时越界值收窄（旧版本写超范围数据）', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('intro_outro_intro_seconds', 9999);
    await prefs.setInt('intro_outro_intro_range', 5);
    await s.load();
    expect(s.introSeconds, s.introRange); // 越界秒数收窄到范围
    expect(s.introRange, 10); // 范围钳到下限
  });
}
