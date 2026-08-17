import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerControlsSettings.instance.reset();
  });

  test('默认值：槽位全空', () {
    final s = PlayerControlsSettings.instance;
    expect(s.topActions, isEmpty); // 默认不放置任何按钮
    expect(s.doubleTapMode, DoubleTapMode.mixed);
    expect(s.showProgressLine, isFalse);
    expect(s.rememberSpeed, isTrue);
    expect(s.lastSpeed, 1.0);
    expect(s.seekSeconds, 10);
    expect(s.customSpeedPresets, isEmpty);
    expect(PlayerControlsSettings.maxTopActions, 5);
  });

  test('槽位：添加/去重/上限', () async {
    final s = PlayerControlsSettings.instance;
    for (final a in PlayerTopAction.values) {
      await s.addTopAction(a);
    }
    // 全部 5 个动作都放得下
    expect(s.topActions, PlayerTopAction.values);
    // 已存在 → 忽略
    await s.addTopAction(PlayerTopAction.speed);
    expect(s.topActions.length, PlayerTopAction.values.length);
  });

  test('槽位：移除后可重新添加', () async {
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.speed);
    await s.addTopAction(PlayerTopAction.subtitle);
    expect(s.topActions, [PlayerTopAction.speed, PlayerTopAction.subtitle]);
    await s.removeTopAction(PlayerTopAction.speed);
    expect(s.topActions, [PlayerTopAction.subtitle]);
    await s.addTopAction(PlayerTopAction.speed);
    expect(s.topActions, [PlayerTopAction.subtitle, PlayerTopAction.speed]);
  });

  test('槽位：拖拽排序', () async {
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.speed);
    await s.addTopAction(PlayerTopAction.subtitle);
    await s.addTopAction(PlayerTopAction.audio);
    // onReorderItem 语义：移除 oldIndex 后插入 newIndex
    await s.reorderTopAction(0, 1);
    expect(s.topActions, [
      PlayerTopAction.subtitle,
      PlayerTopAction.speed,
      PlayerTopAction.audio,
    ]);
    await s.reorderTopAction(1, 2);
    expect(s.topActions, [
      PlayerTopAction.subtitle,
      PlayerTopAction.audio,
      PlayerTopAction.speed,
    ]);
  });

  test('槽位：重置清空', () async {
    final s = PlayerControlsSettings.instance;
    for (final a in PlayerTopAction.values) {
      await s.addTopAction(a);
    }
    await s.resetTopActions();
    expect(s.topActions, isEmpty);
  });

  test('槽位持久化（模拟重启后 load 恢复）', () async {
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.speed);
    await s.addTopAction(PlayerTopAction.aspect);
    await s.load();
    expect(s.topActions, [PlayerTopAction.speed, PlayerTopAction.aspect]);
  });

  test('快进时长设置并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setSeekSeconds(30);
    await s.load(); // 模拟重启
    expect(s.seekSeconds, 30);
  });

  test('时长限制在 1 – 600', () async {
    final s = PlayerControlsSettings.instance;
    await s.setSeekSeconds(0);
    expect(s.seekSeconds, 1);
    await s.setSeekSeconds(9999);
    expect(s.seekSeconds, 600);
  });

  test('旧版按钮时长数据迁移到新 key', () async {
    // 模拟 v1 时代保存的旧 key（按钮时长 25 秒）
    SharedPreferences.setMockInitialValues({
      'player_controls_button_seek': 25,
    });
    final s = PlayerControlsSettings.instance;
    await s.load();
    expect(s.seekSeconds, 25);
  });

  test('自定义倍速预设：添加/去重/上限/持久化/移除/重置', () async {
    final s = PlayerControlsSettings.instance;
    await s.addCustomSpeedPreset(1.3);
    await s.addCustomSpeedPreset(2.8);
    await s.addCustomSpeedPreset(1.3); // 去重
    expect(s.customSpeedPresets, [1.3, 2.8]);

    await s.load(); // 模拟重启
    expect(s.customSpeedPresets, [1.3, 2.8]);

    await s.removeCustomSpeedPreset(1.3);
    expect(s.customSpeedPresets, [2.8]);

    await s.resetCustomSpeedPresets();
    expect(s.customSpeedPresets, isEmpty);
  });

  test('倍速预设范围限制在 0.25 – 4.0', () async {
    final s = PlayerControlsSettings.instance;
    await s.addCustomSpeedPreset(0.1); // 下限钳制
    expect(s.customSpeedPresets.first, PlayerControlsSettings.minSpeed);
    await s.addCustomSpeedPreset(9.9); // 上限钳制
    expect(s.customSpeedPresets.last, PlayerControlsSettings.maxSpeed);
  });

  test('修改设置并持久化（模拟重启后 load 恢复）', () async {
    final s = PlayerControlsSettings.instance;
    await s.setDoubleTapMode(DoubleTapMode.seek);
    await s.setShowProgressLine(true);
    await s.setRememberSpeed(false);
    await s.setSpeed(1.5);
    await s.setSeekSeconds(60);
    await s.addCustomSpeedPreset(1.75);
    await s.addTopAction(PlayerTopAction.speed);

    await s.load();
    expect(s.doubleTapMode, DoubleTapMode.seek);
    expect(s.showProgressLine, isTrue);
    expect(s.rememberSpeed, isFalse);
    expect(s.lastSpeed, 1.5);
    expect(s.seekSeconds, 60);
    expect(s.customSpeedPresets, [1.75]);
    expect(s.topActions, [PlayerTopAction.speed]);
  });
}
