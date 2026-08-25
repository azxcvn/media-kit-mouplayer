import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/subtitle_auto_match.dart';

void main() {
  group('isSameBaseSubtitle（同名字幕候选判定）', () {
    test('视频名前缀 + 支持扩展名 → 命中', () {
      expect(isSameBaseSubtitle('EP01.ass', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01.sc.ass', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01.srt', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01.vtt', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01.json', 'EP01'), isTrue);
      // 大小写不敏感
      expect(isSameBaseSubtitle('ep01.ASS', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01.Ass', 'ep01'), isTrue);
    });

    test('视频名带点号（Episode.01.mp4）', () {
      expect(isSameBaseSubtitle('Episode.01.sc.ass', 'Episode.01'), isTrue);
      expect(isSameBaseSubtitle('Episode.01.ass', 'Episode.01'), isTrue);
    });

    test('不命中：不同视频名 / 非字幕扩展名 / 不在优先级列表', () {
      expect(isSameBaseSubtitle('EP02.ass', 'EP01'), isFalse);
      expect(isSameBaseSubtitle('EP01.mp4', 'EP01'), isFalse);
      expect(isSameBaseSubtitle('EP01.lrc', 'EP01'), isFalse); // lrc 不在优先级列表
      expect(isSameBaseSubtitle('EP01.idx', 'EP01'), isFalse);
      expect(isSameBaseSubtitle('EP01', 'EP01'), isFalse); // 无扩展名
    });

    test('模糊前缀匹配：以视频名开头即可（对齐小喵 startsWith）', () {
      expect(isSameBaseSubtitle('EP01x.ass', 'EP01'), isTrue);
      expect(isSameBaseSubtitle('EP01-Bonus.srt', 'EP01'), isTrue);
    });
  });

  group('langPriority（简体/繁体语言后缀优先级）', () {
    test('简体系统命中 sc/chs/简/zh-cn', () {
      expect(langPriority('.sc', isSC: true, isTC: false), 0);
      expect(langPriority('.chs', isSC: true, isTC: false), 0);
      expect(langPriority('.简中', isSC: true, isTC: false), 0);
      expect(langPriority('.zh-cn', isSC: true, isTC: false), 0);
    });

    test('繁体系统命中 tc/cht/繁/zh-tw', () {
      expect(langPriority('.tc', isSC: false, isTC: true), 0);
      expect(langPriority('.cht', isSC: false, isTC: true), 0);
      expect(langPriority('.繁中', isSC: false, isTC: true), 0);
      expect(langPriority('.zh-tw', isSC: false, isTC: true), 0);
    });

    test('语言不匹配 / 无语言后缀 → 1', () {
      expect(langPriority('.tc', isSC: true, isTC: false), 1); // 简体系遇 tc
      expect(langPriority('.sc', isSC: false, isTC: true), 1); // 繁体系遇 sc
      expect(langPriority('', isSC: true, isTC: true), 1);
      expect(langPriority('.en', isSC: true, isTC: false), 1);
    });
  });

  group('findBestSubtitleFileName（同名字幕自动匹配排序）', () {
    test('完全同名（无后缀）优先于带语言后缀', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP01.sc.ass', 'EP01.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.ass',
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.tc.srt', 'EP01.srt'],
            systemLanguage: 'zh_tw'),
        'EP01.srt',
      );
    });

    test('简体系统（zh_cn）优先 sc/chs，繁体系统优先 tc/cht', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP01.tc.ass', 'EP01.sc.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.sc.ass',
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.sc.ass', 'EP01.tc.ass'],
            systemLanguage: 'zh_tw'),
        'EP01.tc.ass',
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.sc.ass', 'EP01.tc.ass'],
            systemLanguage: 'zh_hk'),
        'EP01.tc.ass',
      );
    });

    test('zh-cn / zh-tw / 简 / 繁 后缀按系统语言命中', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP01.en.ass', 'EP01.zh-cn.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.zh-cn.ass',
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.繁体.ass', 'EP01.简体.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.简体.ass',
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.简体.ass', 'EP01.繁体.ass'],
            systemLanguage: 'zh_tw'),
        'EP01.繁体.ass',
      );
    });

    test('扩展名优先级 ass > srt（先于语言后缀比较）', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP01.sc.srt', 'EP01.tc.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.tc.ass', // ass 优先，即使语言后缀不匹配
      );
      expect(
        findBestSubtitleFileName('EP01', ['EP01.srt', 'EP01.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.ass',
      );
    });

    test('名字越短越优先（同级语言后缀下的兜底）', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP01.ab.ass', 'EP01.a.ass'],
            systemLanguage: 'zh_cn'),
        'EP01.a.ass',
      );
    });

    test('无匹配返回 null', () {
      expect(
        findBestSubtitleFileName('EP01', ['EP02.ass', 'EP01.mp4'],
            systemLanguage: 'zh_cn'),
        isNull,
      );
      expect(
        findBestSubtitleFileName('EP01', <String>[], systemLanguage: 'zh_cn'),
        isNull,
      );
    });

    test('非英文字符视频名 + 模糊前缀匹配', () {
      expect(
        findBestSubtitleFileName('我的视频', ['我的视频.sc.ass', '我的视频.ass'],
            systemLanguage: 'zh_cn'),
        '我的视频.ass',
      );
      expect(
        findBestSubtitleFileName('我的视频', ['我的视频tc.ass', '我的视频sc.ass'],
            systemLanguage: 'zh_cn'),
        '我的视频sc.ass',
      );
    });
  });
}
