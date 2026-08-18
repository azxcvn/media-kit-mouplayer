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
    // 记忆上次倍速默认关闭（用户显式开启后才记住）
    expect(s.rememberSpeed, isFalse);
    expect(s.lastSpeed, 1.0);
    expect(s.seekSeconds, 10);
    expect(s.customSpeedPresets, isEmpty);
    expect(PlayerControlsSettings.maxTopActions, 5);
    // 按钮背景默认关闭（底栏倍速/顶栏图标默认无背景）
    expect(s.showButtonBackground, isFalse);
    // 画面比例默认自动
    expect(s.videoFit, PlayerVideoFit.contain);
    // 长按倍速默认 2.0、指示器开启、首次提示未完成
    expect(s.longPressSpeed, 2.0);
    expect(s.showSpeedIndicator, isTrue);
    expect(s.speedHintShown, isFalse);
    // 保存音量到系统默认开启
    expect(s.saveVolumeToSystem, isTrue);
    // 灵敏度默认 1.0，双指缩小默认开启
    expect(s.volumeSensitivity, 1.0);
    expect(s.brightnessSensitivity, 1.0);
    expect(s.enableShrinkVideo, isTrue);
    // 进度条缩略图默认开启
    expect(s.showThumbnailPreview, isTrue);
  });

  test('长按倍速：设置/持久化/范围钳制/0.1 步进离散', () async {
    final s = PlayerControlsSettings.instance;
    await s.setLongPressSpeed(2.3);
    expect(s.longPressSpeed, 2.3);
    await s.load(); // 模拟重启
    expect(s.longPressSpeed, 2.3);
    // 越界钳制到 1 – 6
    await s.setLongPressSpeed(0.5);
    expect(s.longPressSpeed, PlayerControlsSettings.minLongPressSpeed);
    await s.setLongPressSpeed(9.9);
    expect(s.longPressSpeed, PlayerControlsSettings.maxLongPressSpeed);
    // 0.1 步进离散：2.34 → 2.3
    await s.setLongPressSpeed(2.34);
    expect(s.longPressSpeed, closeTo(2.3, 0.0001));
  });

  test('倍速播放指示器：默认开启，可开关并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setShowSpeedIndicator(false);
    expect(s.showSpeedIndicator, isFalse);
    await s.load();
    expect(s.showSpeedIndicator, isFalse);
    await s.setShowSpeedIndicator(true);
    expect(s.showSpeedIndicator, isTrue);
  });

  test('首次提示：默认未完成，标记后持久化且不重复', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.speedHintShown, isFalse);
    await s.markSpeedHintShown();
    expect(s.speedHintShown, isTrue);
    await s.load();
    expect(s.speedHintShown, isTrue);
    await s.markSpeedHintShown(); // 幂等
    expect(s.speedHintShown, isTrue);
  });

  test('保存音量到系统：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setSaveVolumeToSystem(false);
    expect(s.saveVolumeToSystem, isFalse);
    await s.load();
    expect(s.saveVolumeToSystem, isFalse);
    await s.setSaveVolumeToSystem(true);
    expect(s.saveVolumeToSystem, isTrue);
  });

  test('手势灵敏度：设置/持久化/范围钳制', () async {
    final s = PlayerControlsSettings.instance;
    await s.setVolumeSensitivity(1.5);
    await s.setBrightnessSensitivity(0.8);
    await s.load();
    expect(s.volumeSensitivity, 1.5);
    expect(s.brightnessSensitivity, 0.8);
    // 越界钳制
    await s.setVolumeSensitivity(0.1);
    expect(s.volumeSensitivity, PlayerControlsSettings.minGestureSensitivity);
    await s.setBrightnessSensitivity(9.9);
    expect(
      s.brightnessSensitivity,
      PlayerControlsSettings.maxGestureSensitivity,
    );
  });

  test('双指缩小视频：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setEnableShrinkVideo(false);
    expect(s.enableShrinkVideo, isFalse);
    await s.load();
    expect(s.enableShrinkVideo, isFalse);
    await s.setEnableShrinkVideo(true);
    expect(s.enableShrinkVideo, isTrue);
  });

  test('进度条缩略图：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setShowThumbnailPreview(false);
    expect(s.showThumbnailPreview, isFalse);
    await s.load();
    expect(s.showThumbnailPreview, isFalse);
    await s.setShowThumbnailPreview(true);
    expect(s.showThumbnailPreview, isTrue);
  });

  test('按钮背景：默认关闭，可开关并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setShowButtonBackground(true);
    expect(s.showButtonBackground, isTrue);
    await s.load(); // 模拟重启
    expect(s.showButtonBackground, isTrue);
    await s.setShowButtonBackground(false);
    expect(s.showButtonBackground, isFalse);
  });

  test('画面比例：默认自动，可切换并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setVideoFit(PlayerVideoFit.ratio16x9);
    expect(s.videoFit, PlayerVideoFit.ratio16x9);
    await s.load(); // 模拟重启
    expect(s.videoFit, PlayerVideoFit.ratio16x9);
    await s.setVideoFit(PlayerVideoFit.cover);
    expect(s.videoFit, PlayerVideoFit.cover);
  });

  test('槽位：添加/去重/上限', () async {
    final s = PlayerControlsSettings.instance;
    for (final a in PlayerTopAction.values) {
      await s.addTopAction(a);
    }
    // 全部动作都放得下（倍速不在顶栏动作之列，见 PlayerTopAction 注释）
    expect(s.topActions, PlayerTopAction.values);
    // 已存在 → 忽略
    await s.addTopAction(PlayerTopAction.subtitle);
    expect(s.topActions.length, PlayerTopAction.values.length);
  });

  test('槽位：移除后可重新添加', () async {
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.subtitle);
    await s.addTopAction(PlayerTopAction.danmaku);
    expect(s.topActions, [PlayerTopAction.subtitle, PlayerTopAction.danmaku]);
    await s.removeTopAction(PlayerTopAction.subtitle);
    expect(s.topActions, [PlayerTopAction.danmaku]);
    await s.addTopAction(PlayerTopAction.subtitle);
    expect(s.topActions, [PlayerTopAction.danmaku, PlayerTopAction.subtitle]);
  });

  test('槽位：拖拽排序', () async {
    final s = PlayerControlsSettings.instance;
    await s.addTopAction(PlayerTopAction.subtitle);
    await s.addTopAction(PlayerTopAction.danmaku);
    await s.addTopAction(PlayerTopAction.audio);
    // onReorderItem 语义：移除 oldIndex 后插入 newIndex
    await s.reorderTopAction(0, 1);
    expect(s.topActions, [
      PlayerTopAction.danmaku,
      PlayerTopAction.subtitle,
      PlayerTopAction.audio,
    ]);
    await s.reorderTopAction(1, 2);
    expect(s.topActions, [
      PlayerTopAction.danmaku,
      PlayerTopAction.audio,
      PlayerTopAction.subtitle,
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
    await s.addTopAction(PlayerTopAction.subtitle);
    await s.addTopAction(PlayerTopAction.aspect);
    await s.load();
    expect(s.topActions, [PlayerTopAction.subtitle, PlayerTopAction.aspect]);
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
    await s.setRememberSpeed(true); // 默认关闭，显式开启后应持久化
    await s.setSpeed(1.5);
    await s.setSeekSeconds(60);
    await s.addCustomSpeedPreset(1.75);
    await s.addTopAction(PlayerTopAction.subtitle);

    await s.load();
    expect(s.doubleTapMode, DoubleTapMode.seek);
    expect(s.showProgressLine, isTrue);
    expect(s.rememberSpeed, isTrue);
    expect(s.lastSpeed, 1.5);
    expect(s.seekSeconds, 60);
    expect(s.customSpeedPresets, [1.75]);
    expect(s.topActions, [PlayerTopAction.subtitle]);
  });
}
