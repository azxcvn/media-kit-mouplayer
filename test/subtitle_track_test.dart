import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/subtitle_track.dart';

void main() {
  group('SubtitleTrack（工作.md 阶段1 第 3 点）', () {
    test('displayTitle：优先标题、其次语言、最后回退轨道 id', () {
      expect(
        const SubtitleTrack(id: '1', title: '简体中文', language: 'chi')
            .displayTitle,
        '简体中文',
      );
      expect(
        const SubtitleTrack(id: '2', language: 'eng').displayTitle,
        'eng',
      );
      expect(const SubtitleTrack(id: '3').displayTitle, '轨道 3');
    });

    test('isStyled：ASS/SSA 内嵌样式字幕判定（大小写不敏感）', () {
      expect(const SubtitleTrack(id: '1', codec: 'ass').isStyled, isTrue);
      expect(const SubtitleTrack(id: '2', codec: 'SSA').isStyled, isTrue);
      expect(const SubtitleTrack(id: '3', codec: 'srt').isStyled, isFalse);
      expect(const SubtitleTrack(id: '4', codec: 'webvtt').isStyled, isFalse);
      expect(const SubtitleTrack(id: '5').isStyled, isFalse);
    });
  });

  group('subtitleTrackLabel', () {
    test('普通内嵌字幕：标题 + 格式', () {
      final label = subtitleTrackLabel(
        const SubtitleTrack(id: '1', title: '中文', codec: 'srt'),
      );
      expect(label, '中文 · srt');
    });

    test('外挂字幕带「外挂」标记', () {
      final label = subtitleTrackLabel(
        const SubtitleTrack(id: '2', title: '双语', codec: 'ass', external: true),
      );
      expect(label, '双语 · 外挂 · ass');
    });

    test('无标题无格式：只显示回退名', () {
      expect(subtitleTrackLabel(const SubtitleTrack(id: '7')), '轨道 7');
    });
  });

  group('isSupportedSubtitleFile', () {
    test('支持常见字幕扩展名（大小写不敏感）', () {
      expect(isSupportedSubtitleFile('a.srt'), isTrue);
      expect(isSupportedSubtitleFile('b.ASS'), isTrue);
      expect(isSupportedSubtitleFile('c.vtt'), isTrue);
      expect(isSupportedSubtitleFile('d.ssa'), isTrue);
      expect(isSupportedSubtitleFile('e.sup'), isTrue);
    });

    test('非字幕扩展名 / 无扩展名返回 false', () {
      expect(isSupportedSubtitleFile('video.mp4'), isFalse);
      expect(isSupportedSubtitleFile('video.mkv'), isFalse);
      expect(isSupportedSubtitleFile('noext'), isFalse);
      expect(isSupportedSubtitleFile(''), isFalse);
      expect(isSupportedSubtitleFile('trailing.'), isFalse);
    });
  });

  group('isFontFile', () {
    test('支持 .ttf/.otf/.ttc（大小写不敏感）', () {
      expect(isFontFile('a.ttf'), isTrue);
      expect(isFontFile('b.OTF'), isTrue);
      expect(isFontFile('c.ttc'), isTrue);
      expect(isFontFile('d.otc'), isTrue);
    });

    test('非字体 / 无扩展名返回 false', () {
      expect(isFontFile('a.srt'), isFalse);
      expect(isFontFile('video.jpg'), isFalse);
      expect(isFontFile('noext'), isFalse);
      expect(isFontFile(''), isFalse);
    });
  });

  group('SubtitleAlign', () {
    test('byMpvValue：未知值回退居中', () {
      expect(SubtitleAlign.byMpvValue('left'), SubtitleAlign.left);
      expect(SubtitleAlign.byMpvValue('right'), SubtitleAlign.right);
      expect(SubtitleAlign.byMpvValue('center'), SubtitleAlign.center);
      expect(SubtitleAlign.byMpvValue('garbage'), SubtitleAlign.center);
    });
  });

  group('SubtitlePresetColor', () {
    test('byHex：已知色匹配、未知色回退白色', () {
      expect(SubtitlePresetColor.byHex('#FFEB3B').label, '黄色');
      expect(SubtitlePresetColor.byHex('#ffffff').label, '白色');
      expect(SubtitlePresetColor.byHex('#000000').label, '白色');
    });
  });

  group('RGBA 颜色转换（mpv #RRGGBB / #AARRGGBB）', () {
    test('rgbaToMpvColor：不透明输出 6 位 RRGGBB', () {
      expect(
        rgbaToMpvColor(const (r: 255, g: 255, b: 255, a: 255)),
        '#FFFFFF',
      );
      expect(
        rgbaToMpvColor(const (r: 0, g: 0, b: 0, a: 255)),
        '#000000',
      );
      expect(
        rgbaToMpvColor(const (r: 0xFF, g: 0xEB, b: 0x3B, a: 255)),
        '#FFEB3B',
      );
    });

    test('rgbaToMpvColor：带透明度输出 8 位 AARRGGBB（alpha 在前）', () {
      expect(
        rgbaToMpvColor(const (r: 0xFF, g: 0xFF, b: 0xFF, a: 0xD6)),
        '#D6FFFFFF',
      );
      expect(
        rgbaToMpvColor(const (r: 0x6A, g: 0x67, b: 0x8C, a: 0x26)),
        '#266A678C',
      );
    });

    test('mpvColorToRgba：6 位解析为不透明', () {
      expect(
        mpvColorToRgba('#FFFFFF'),
        const (r: 0xFF, g: 0xFF, b: 0xFF, a: 0xFF),
      );
      expect(
        mpvColorToRgba('FFEB3B'), // 允许不带 #/小写
        const (r: 0xFF, g: 0xEB, b: 0x3B, a: 0xFF),
      );
    });

    test('mpvColorToRgba：8 位按 AARRGGBB 解码（与 小喵 #AARRGGBB 一致）', () {
      expect(
        mpvColorToRgba('#D6FFFFFF'),
        const (r: 0xFF, g: 0xFF, b: 0xFF, a: 0xD6),
      );
      expect(
        mpvColorToRgba('#266A678C'),
        const (r: 0x6A, g: 0x67, b: 0x8C, a: 0x26),
      );
    });

    test('往返一致：rgba → hex → rgba', () {
      const c = (r: 34, g: 200, b: 133, a: 88);
      expect(mpvColorToRgba(rgbaToMpvColor(c)), c);
    });

    test('非法输入回退纯黑不透明', () {
      expect(mpvColorToRgba('oopsPlane'), const (r: 0, g: 0, b: 0, a: 255));
    });
  });
}
