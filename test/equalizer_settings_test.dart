import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/equalizer_preset.dart';
import 'package:moumou/services/equalizer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频均衡器设置服务测试：默认值、钳制、预设应用、重置与持久化。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EqualizerSettings.instance.reset();
  });

  final s = EqualizerSettings.instance;

  test('默认值：关闭 / 全平 / 低音与虚拟 0 / 无预设', () {
    expect(s.enabled, isFalse);
    expect(s.bands, [0, 0, 0, 0, 0]);
    expect(s.bassBoost, 0);
    expect(s.virtualizer, 0);
    expect(s.presetId, isNull);
    expect(s.isFlat, isTrue);
  });

  test('开关持久化（模拟重启 load）', () async {
    await s.setEnabled(true);
    expect(s.enabled, isTrue);
    await s.load();
    expect(s.enabled, isTrue);
  });

  test('setBand 取整到 1dB 并钳制到 -15~+15，且清空预设高亮', () async {
    await s.setBand(0, 5.4);
    expect(s.bands[0], 5);
    await s.setBand(1, 99);
    expect(s.bands[1], 15); // 超上限钳制
    await s.setBand(2, -99);
    expect(s.bands[2], -15); // 超下限钳制
    expect(s.presetId, isNull);
  });

  test('applyPreset 覆盖 5 段并记录预设 id', () async {
    final cinema = equalizerPresetById('cinema')!;
    await s.applyPreset(cinema);
    expect(s.bands, cinema.bands);
    expect(s.presetId, 'cinema');
  });

  test('低音增强 / 虚拟环绕取整并钳制到 0-100', () async {
    await s.setBassBoost(50);
    expect(s.bassBoost, 50);
    await s.setBassBoost(999);
    expect(s.bassBoost, 100);
    await s.setBassBoost(-3);
    expect(s.bassBoost, 0);

    await s.setVirtualizer(75);
    expect(s.virtualizer, 75);
    await s.setVirtualizer(-10);
    expect(s.virtualizer, 0);
  });

  test('resetValues 归零各项（保留 enabled 状态）', () async {
    await s.setEnabled(true);
    await s.applyPreset(equalizerPresetById('cinema')!);
    await s.setBassBoost(50);
    await s.setVirtualizer(30);
    expect(s.isFlat, isFalse);

    await s.resetValues();
    expect(s.bands, [0, 0, 0, 0, 0]);
    expect(s.bassBoost, 0);
    expect(s.virtualizer, 0);
    expect(s.presetId, isNull);
    expect(s.enabled, isTrue); // 开关不受重置影响
  });

  test('预设 id 持久化后重启可恢复（load 回读）', () async {
    await s.applyPreset(equalizerPresetById('bass')!);
    await s.setBassBoost(40);
    await s.setVirtualizer(20);
    await s.load();
    expect(s.presetId, 'bass');
    expect(s.bands, equalizerPresetById('bass')!.bands);
    expect(s.bassBoost, 40);
    expect(s.virtualizer, 20);
  });

  test('旧数据指向已删除预设 → load 回退 null', () async {
    // 直接写一个不存在的预设 id 模拟旧数据
    final prefs = await (s.ensureLoaded()).then((_) async =>
        await SharedPreferences.getInstance());
    await prefs.setString('eq_preset', 'removed_preset');
    await s.load();
    expect(s.presetId, isNull);
  });
}
