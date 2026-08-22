import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/services/intro_outro_tracker.dart';
import 'package:moumou/utils/intro_outro_skip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 片头片尾跟踪器测试（设置单例 + mock prefs）：
/// - markReady 前位置事件不评估；
/// - 片头/片尾每集各触发一次（seek/切集异步窗口内不重复）；
/// - 位置越过片头即标记（回拖进片头不重复跳）；
/// - 恢复点感知：恢复点 > 0 不跳片头；恢复点落在片尾不立即切集；
/// - reset 后重新评估（新集从头）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IntroOutroSettings.instance.resetForTest();
  });

  final s = IntroOutroSettings.instance;

  Future<IntroOutroTracker> tracker({
    bool enabled = true,
    int introSeconds = 0,
    int outroSeconds = 0,
  }) async {
    await s.setEnabled(enabled);
    await s.setIntroSeconds(introSeconds);
    await s.setOutroSeconds(outroSeconds);
    return IntroOutroTracker(s);
  }

  Duration d(int seconds) => Duration(seconds: seconds);

  group('就绪门控', () {
    test('markReady 前位置事件不评估', () async {
      final t = await tracker(introSeconds: 90);
      expect(
        t.onPositionChanged(d(10), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });
  });

  group('跳过片头', () {
    test('片头范围内首次事件 → skipIntro，随后不重复', () async {
      final t = await tracker(introSeconds: 90);
      t.markReady();
      expect(
        t.onPositionChanged(d(10), d(600), hasNext: true),
        IntroOutroAction.skipIntro,
      );
      // seek 异步窗口内继续来位置事件：不重复触发
      expect(
        t.onPositionChanged(d(20), d(600), hasNext: true),
        IntroOutroAction.none,
      );
      // 回拖进片头：也不重复跳
      expect(
        t.onPositionChanged(d(5), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });

    test('位置越过片头即标记：先越过后回拖不跳', () async {
      final t = await tracker(introSeconds: 90);
      t.markReady();
      // 用户主动 seek 到 120（越过片头，未在片头范围内停留）
      expect(
        t.onPositionChanged(d(120), d(600), hasNext: true),
        IntroOutroAction.none,
      );
      // 回拖到 30：不应再被跳走
      expect(
        t.onPositionChanged(d(30), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });
  });

  group('跳过片尾', () {
    test('进入片尾范围且有下一集 → nextEpisode，随后不重复', () async {
      final t = await tracker(outroSeconds: 10);
      t.markReady();
      expect(
        t.onPositionChanged(d(595), d(600), hasNext: true),
        IntroOutroAction.nextEpisode,
      );
      // 切集异步窗口内继续来位置事件：不重复触发
      expect(
        t.onPositionChanged(d(598), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });

    test('无下一集 → 不动作（交给 EOF 流程）', () async {
      final t = await tracker(outroSeconds: 10);
      t.markReady();
      expect(
        t.onPositionChanged(d(595), d(600), hasNext: false),
        IntroOutroAction.none,
      );
    });
  });

  group('恢复进度感知', () {
    test('恢复点 > 0：不立即跳片头', () async {
      final t = await tracker(introSeconds: 90);
      t.markResumedPosition(d(50), d(600));
      t.markReady();
      expect(
        t.onPositionChanged(d(50), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });

    test('恢复点落在片尾：不立即切集', () async {
      final t = await tracker(outroSeconds: 10);
      t.markResumedPosition(d(595), d(600));
      t.markReady();
      expect(
        t.onPositionChanged(d(595), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });

    test('恢复点 0（从头播）：片头正常跳过', () async {
      final t = await tracker(introSeconds: 90);
      t.markResumedPosition(Duration.zero, d(600));
      t.markReady();
      expect(
        t.onPositionChanged(d(10), d(600), hasNext: true),
        IntroOutroAction.skipIntro,
      );
    });
  });

  group('切集重置', () {
    test('reset 后新集重新评估（片头可再次跳过）', () async {
      final t = await tracker(introSeconds: 90);
      t.markReady();
      t.onPositionChanged(d(10), d(600), hasNext: true); // 第一集跳过
      t.reset();
      t.markReady();
      expect(
        t.onPositionChanged(d(10), d(600), hasNext: true),
        IntroOutroAction.skipIntro,
      );
    });

    test('功能关闭时不产生动作', () async {
      final t = await tracker(enabled: false, introSeconds: 90);
      t.markReady();
      expect(
        t.onPositionChanged(d(10), d(600), hasNext: true),
        IntroOutroAction.none,
      );
    });
  });
}
