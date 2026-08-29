import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/danmaku_local_file.dart';

/// 同名弹幕文件查找纯函数测试（9 种命名规则 + 优先级 + 排除视频自身）。
void main() {
  group('danmakuCandidateNames（9 种命名规则）', () {
    test('按优先级生成全部候选', () {
      final names = danmakuCandidateNames('EP01');
      expect(names, [
        'EP01.xml',
        'EP01.danmaku.xml',
        'EP01_danmaku.xml',
        'EP01.dandan.xml',
        'EP01_dandan.xml',
        'EP01.acfun.xml',
        'danmaku.xml',
        '弹幕.xml',
        'EP01', // 无扩展名
      ]);
    });

    test('视频名含点号（Episode.01）也正常拼接', () {
      final names = danmakuCandidateNames('Episode.01');
      expect(names.first, 'Episode.01.xml');
      expect(names[1], 'Episode.01.danmaku.xml');
      expect(names.last, 'Episode.01');
    });
  });

  group('findLocalDanmakuFileName（优先级命中）', () {
    test('同名 .xml 优先级最高', () {
      final found = findLocalDanmakuFileName(
        'EP01',
        'EP01.mp4',
        ['EP01.xml', 'EP01.danmaku.xml', 'danmaku.xml'],
      );
      expect(found, 'EP01.xml');
    });

    test('无同名时按顺序回退（.danmaku.xml → _danmaku.xml → …）', () {
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01.danmaku.xml']),
        'EP01.danmaku.xml',
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01_danmaku.xml']),
        'EP01_danmaku.xml',
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01.dandan.xml']),
        'EP01.dandan.xml',
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01_dandan.xml']),
        'EP01_dandan.xml',
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01.acfun.xml']),
        'EP01.acfun.xml',
      );
    });

    test('目录级通用名 danmaku.xml / 弹幕.xml 兜底命中', () {
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['danmaku.xml']),
        'danmaku.xml',
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['弹幕.xml']),
        '弹幕.xml',
      );
    });

    test('无扩展名候选（与视频同名的裸文件）', () {
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01']),
        'EP01',
      );
    });

    test('视频本身无扩展名时不把视频自身当弹幕文件', () {
      // 视频文件就叫「EP01」（无扩展名），同名裸候选会与视频重名 → 排除
      final found = findLocalDanmakuFileName('EP01', 'EP01', ['EP01']);
      expect(found, isNull);
      // 但同名 .xml 仍可命中
      expect(
        findLocalDanmakuFileName('EP01', 'EP01', ['EP01', 'EP01.xml']),
        'EP01.xml',
      );
    });

    test('无匹配返回 null（大小写敏感，不误伤相似名）', () {
      expect(findLocalDanmakuFileName('EP01', 'EP01.mp4', []), isNull);
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['ep01.xml', 'EP02.xml']),
        isNull,
      );
      expect(
        findLocalDanmakuFileName('EP01', 'EP01.mp4', ['EP01.mp4']),
        isNull,
      );
    });
  });

  group('isSupportedDanmakuFile（弹幕文件选择器过滤）', () {
    test('.xml 命中（大小写不敏感）', () {
      expect(isSupportedDanmakuFile('EP01.xml'), isTrue);
      expect(isSupportedDanmakuFile('EP01.XML'), isTrue);
      expect(isSupportedDanmakuFile('弹幕.xml'), isTrue);
      expect(isSupportedDanmakuFile('EP01.danmaku.xml'), isTrue);
    });

    test('其他格式不命中', () {
      expect(isSupportedDanmakuFile('EP01.ass'), isFalse);
      expect(isSupportedDanmakuFile('EP01.json'), isFalse);
      expect(isSupportedDanmakuFile('EP01.mp4'), isFalse);
      expect(isSupportedDanmakuFile('EP01'), isFalse);
      expect(isSupportedDanmakuFile('EP01.xmlx'), isFalse);
    });
  });
}
