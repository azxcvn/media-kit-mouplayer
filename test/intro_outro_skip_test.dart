import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/intro_outro_skip.dart';

/// 片头片尾动作决策纯函数测试：
/// - 开关/时长为 0 等前置条件不产生动作；
/// - 片头范围内（未处理）→ skipIntro；已处理 / 秒数为 0 /
///   整集都是片头（守卫）→ 不跳；
/// - 片尾范围内且有下一集 → nextEpisode；无下一集 / 已处理 /
///   整集都是片尾（守卫）→ 不跳；
/// - 同时命中片头与片尾时片头优先。
void main() {
  IntroOutroAction resolve({
    bool enabled = true,
    int introSeconds = 0,
    int outroSeconds = 0,
    double positionSeconds = 0,
    double durationSeconds = 100,
    bool introHandled = false,
    bool outroHandled = false,
    bool hasNext = true,
  }) =>
      resolveIntroOutroAction(
        enabled: enabled,
        introSeconds: introSeconds,
        outroSeconds: outroSeconds,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        introHandled: introHandled,
        outroHandled: outroHandled,
        hasNext: hasNext,
      );

  group('前置条件', () {
    test('关闭开关 → 不动作', () {
      expect(resolve(enabled: false, introSeconds: 90), IntroOutroAction.none);
      expect(
        resolve(enabled: false, outroSeconds: 10, positionSeconds: 95),
        IntroOutroAction.none,
      );
    });

    test('时长未知（≤0）→ 不动作', () {
      expect(
        resolve(introSeconds: 90, durationSeconds: 0),
        IntroOutroAction.none,
      );
      expect(
        resolve(outroSeconds: 10, durationSeconds: -1),
        IntroOutroAction.none,
      );
    });

    test('片头/片尾秒数都为 0 → 不动作', () {
      expect(resolve(positionSeconds: 50), IntroOutroAction.none);
    });
  });

  group('跳过片头', () {
    test('位置在片头范围内且未处理 → skipIntro', () {
      expect(
        resolve(introSeconds: 90, positionSeconds: 30),
        IntroOutroAction.skipIntro,
      );
    });

    test('片头已处理 → 不跳', () {
      expect(
        resolve(introSeconds: 90, positionSeconds: 30, introHandled: true),
        IntroOutroAction.none,
      );
    });

    test('位置已越过片头 → 不跳', () {
      expect(
        resolve(introSeconds: 90, positionSeconds: 120),
        IntroOutroAction.none,
      );
    });

    test('片头长度 ≥ 视频总长（整集都是片头）→ 不跳（防 EOF 误连播）', () {
      expect(
        resolve(introSeconds: 120, durationSeconds: 120, positionSeconds: 10),
        IntroOutroAction.none,
      );
    });
  });

  group('跳过片尾', () {
    test('剩余时长 ≤ 片尾秒数且有下一集 → nextEpisode', () {
      expect(
        resolve(outroSeconds: 10, positionSeconds: 95, durationSeconds: 100),
        IntroOutroAction.nextEpisode,
      );
    });

    test('无下一集 → 不动作（交给 EOF 流程）', () {
      expect(
        resolve(
          outroSeconds: 10,
          positionSeconds: 95,
          durationSeconds: 100,
          hasNext: false,
        ),
        IntroOutroAction.none,
      );
    });

    test('片尾已处理 → 不重复跳', () {
      expect(
        resolve(
          outroSeconds: 10,
          positionSeconds: 96,
          durationSeconds: 100,
          outroHandled: true,
        ),
        IntroOutroAction.none,
      );
    });

    test('片尾长度 ≥ 视频总长（整集都是片尾）→ 不跳', () {
      expect(
        resolve(outroSeconds: 100, durationSeconds: 100, positionSeconds: 10),
        IntroOutroAction.none,
      );
    });
  });

  test('片头优先：同位置同时命中片头与片尾 → skipIntro', () {
    expect(
      resolve(
        introSeconds: 90,
        outroSeconds: 90,
        positionSeconds: 20,
        durationSeconds: 100,
      ),
      IntroOutroAction.skipIntro,
    );
  });
}
