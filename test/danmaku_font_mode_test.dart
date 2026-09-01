import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_font_mode.dart';

/// 弹幕字体三态解析纯函数测试（工作.md 第 4 点）。
void main() {
  test('三态解析：跟随系统恒为 null', () {
    expect(
      resolveDanmakuFontFamily(
        mode: DanmakuFontMode.followSystem,
        customFontFamily: 'D',
        appFontFamily: 'F',
      ),
      isNull,
    );
  });

  test('三态解析：跟随 App 返回 App 字体（App 为默认时回落 null）', () {
    expect(
      resolveDanmakuFontFamily(
        mode: DanmakuFontMode.followApp,
        customFontFamily: 'D',
        appFontFamily: 'F',
      ),
      'F',
    );
    expect(
      resolveDanmakuFontFamily(
        mode: DanmakuFontMode.followApp,
        customFontFamily: 'D',
        appFontFamily: null,
      ),
      isNull,
    );
  });

  test('三态解析：自定义返回自定义字体', () {
    expect(
      resolveDanmakuFontFamily(
        mode: DanmakuFontMode.custom,
        customFontFamily: 'D',
        appFontFamily: 'F',
      ),
      'D',
    );
    expect(
      resolveDanmakuFontFamily(
        mode: DanmakuFontMode.custom,
        customFontFamily: null,
        appFontFamily: 'F',
      ),
      isNull,
    );
  });
}
