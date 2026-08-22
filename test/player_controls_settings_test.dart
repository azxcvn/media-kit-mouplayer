import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/models/player_loop.dart';
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
    // 进度条缩略图默认关闭（省后台解码与缓存占用）
    expect(s.showThumbnailPreview, isFalse);
    // 「已观看」进度阈值默认 95%
    expect(s.watchThreshold, 0.95);
    // 自动连播 / 播放完毕自动退出默认开启，循环播放默认关闭
    expect(s.autoNext, isTrue);
    expect(s.autoExit, isTrue);
    expect(s.loopMode, LoopMode.off);
    // 视频方向默认自动；播放界面动画默认开启（工作.md 第 5/7 点）
    expect(s.videoOrientation, VideoOrientationMode.auto);
    expect(s.playerAnimations, isTrue);
    // 顶部信息默认：时间与电量同时显示（工作.md 第 12 点）
    expect(s.topStatusDisplay, TopStatusDisplay.both);
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

  test('进度条缩略图：默认关闭，可开启并持久化', () async {
    final s = PlayerControlsSettings.instance;
    await s.setShowThumbnailPreview(true);
    expect(s.showThumbnailPreview, isTrue);
    await s.load();
    expect(s.showThumbnailPreview, isTrue);
    await s.setShowThumbnailPreview(false);
    expect(s.showThumbnailPreview, isFalse);
  });

  test('「已观看」进度阈值：默认 95%，5% 步进/范围 5%-100%/持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.watchThreshold, 0.95);
    await s.setWatchThreshold(0.8);
    expect(s.watchThreshold, 0.8);
    await s.load(); // 模拟重启
    expect(s.watchThreshold, 0.8);
    // 就近 5% 对齐：83% → 85%，97% → 95%，98% → 100%
    await s.setWatchThreshold(0.83);
    expect(s.watchThreshold, 0.85);
    await s.setWatchThreshold(0.97);
    expect(s.watchThreshold, 0.95);
    await s.setWatchThreshold(0.98);
    expect(s.watchThreshold, 1.0);
    // 越界钳制到 5% – 100%
    await s.setWatchThreshold(0.01);
    expect(s.watchThreshold, PlayerControlsSettings.minWatchThreshold);
    await s.setWatchThreshold(1.5);
    expect(s.watchThreshold, PlayerControlsSettings.maxWatchThreshold);
  });

  test('「已观看」进度阈值：旧值（1% 粒度）迁移后就近 5% 对齐', () async {
    // 旧版本以 1% 粒度保存（0.5 – 1.0），load 时钳制 + 就近对齐 5% 档位
    SharedPreferences.setMockInitialValues({
      'player_controls_watch_threshold': 0.93,
    });
    final s = PlayerControlsSettings.instance;
    await s.load();
    expect(s.watchThreshold, 0.95); // 93% → 95%

    SharedPreferences.setMockInitialValues({
      'player_controls_watch_threshold': 0.62,
    });
    await s.load();
    expect(s.watchThreshold, 0.60); // 62% → 60%

    SharedPreferences.setMockInitialValues({
      'player_controls_watch_threshold': 0.02, // 旧范围外，钳制到下限
    });
    await s.load();
    expect(s.watchThreshold, PlayerControlsSettings.minWatchThreshold);
  });

  test('自动连播：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.autoNext, isTrue);
    await s.setAutoNext(false);
    expect(s.autoNext, isFalse);
    await s.load(); // 模拟重启
    expect(s.autoNext, isFalse);
    await s.setAutoNext(true);
    expect(s.autoNext, isTrue);
  });

  test('播放完毕自动退出：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.autoExit, isTrue);
    await s.setAutoExit(false);
    expect(s.autoExit, isFalse);
    await s.load(); // 模拟重启
    expect(s.autoExit, isFalse);
    await s.setAutoExit(true);
    expect(s.autoExit, isTrue);
  });

  test('循环播放模式：默认关闭，可切换并持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.loopMode, LoopMode.off);
    await s.setLoopMode(LoopMode.loopAll);
    expect(s.loopMode, LoopMode.loopAll);
    await s.load(); // 模拟重启
    expect(s.loopMode, LoopMode.loopAll);
    await s.setLoopMode(LoopMode.repeatOne);
    expect(s.loopMode, LoopMode.repeatOne);
    await s.setLoopMode(LoopMode.off);
    expect(s.loopMode, LoopMode.off);
  });

  test('视频方向：默认自动，可切换并持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.videoOrientation, VideoOrientationMode.auto);
    await s.setVideoOrientation(VideoOrientationMode.portrait);
    expect(s.videoOrientation, VideoOrientationMode.portrait);
    await s.load(); // 模拟重启
    expect(s.videoOrientation, VideoOrientationMode.portrait);
    await s.setVideoOrientation(VideoOrientationMode.landscape);
    expect(s.videoOrientation, VideoOrientationMode.landscape);
    await s.load();
    expect(s.videoOrientation, VideoOrientationMode.landscape);
    await s.setVideoOrientation(VideoOrientationMode.auto);
    expect(s.videoOrientation, VideoOrientationMode.auto);
  });

  test('播放界面动画：默认开启，可关闭并持久化', () async {
    final s = PlayerControlsSettings.instance;
    expect(s.playerAnimations, isTrue);
    await s.setPlayerAnimations(false);
    expect(s.playerAnimations, isFalse);
    await s.load(); // 模拟重启
    expect(s.playerAnimations, isFalse);
    await s.setPlayerAnimations(true);
    expect(s.playerAnimations, isTrue);
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
    // 顶栏动作总数超过槽位上限（9 > maxTopActions=5）：只放得下前 5 个
    expect(
      PlayerTopAction.values.length,
      greaterThan(PlayerControlsSettings.maxTopActions),
    );
    for (final a in PlayerTopAction.values) {
      await s.addTopAction(a);
    }
    expect(s.topActions.length, PlayerControlsSettings.maxTopActions);
    // 已存在 → 忽略（重复添加不增加）
    await s.addTopAction(PlayerTopAction.subtitle);
    expect(s.topActions.length, PlayerControlsSettings.maxTopActions);
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
    await s.setWatchThreshold(0.85);
    await s.setAutoNext(false);
    await s.setAutoExit(false);
    await s.setLoopMode(LoopMode.loopAll);
    await s.setTopStatusDisplay(TopStatusDisplay.time);

    await s.load();
    expect(s.doubleTapMode, DoubleTapMode.seek);
    expect(s.showProgressLine, isTrue);
    expect(s.rememberSpeed, isTrue);
    expect(s.lastSpeed, 1.5);
    expect(s.seekSeconds, 60);
    expect(s.customSpeedPresets, [1.75]);
    expect(s.topActions, [PlayerTopAction.subtitle]);
    expect(s.watchThreshold, 0.85);
    expect(s.autoNext, isFalse);
    expect(s.autoExit, isFalse);
    expect(s.loopMode, LoopMode.loopAll);
    expect(s.topStatusDisplay, TopStatusDisplay.time);
  });

  test('顶部信息显示：关闭/时间/电量/两者切换并持久化（工作.md 第 12 点）', () async {
    final s = PlayerControlsSettings.instance;
    await s.setTopStatusDisplay(TopStatusDisplay.off);
    expect(s.topStatusDisplay, TopStatusDisplay.off);
    await s.load(); // 模拟重启
    expect(s.topStatusDisplay, TopStatusDisplay.off);
    await s.setTopStatusDisplay(TopStatusDisplay.battery);
    expect(s.topStatusDisplay, TopStatusDisplay.battery);
    await s.setTopStatusDisplay(TopStatusDisplay.both);
    expect(s.topStatusDisplay, TopStatusDisplay.both);
    await s.setTopStatusDisplay(TopStatusDisplay.time);
    expect(s.topStatusDisplay, TopStatusDisplay.time);
    await s.setTopStatusDisplay(TopStatusDisplay.time); // 幂等
    expect(s.topStatusDisplay, TopStatusDisplay.time);
  });
}
