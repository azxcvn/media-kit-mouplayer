import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/audio_track.dart';

void main() {
  group('AudioTrack 展示名', () {
    test('优先标题，其次语言，回退「音轨 N」', () {
      expect(
        const AudioTrack(id: '1', title: '国语', language: 'zh').displayTitle,
        '国语',
      );
      expect(
        const AudioTrack(id: '2', language: 'jpn').displayTitle,
        'jpn',
      );
      expect(const AudioTrack(id: '3').displayTitle, '音轨 3');
      // 空白标题按无标题处理
      expect(
        const AudioTrack(id: '4', title: '  ', language: 'eng').displayTitle,
        'eng',
      );
    });
  });

  group('AudioChannels 枚举', () {
    test('五个声道选项与标签', () {
      expect(AudioChannels.values.length, 5);
      expect(AudioChannels.auto.label, '自动');
      expect(AudioChannels.autoSafe.label, '安全自动');
      expect(AudioChannels.mono.label, '单声道');
      expect(AudioChannels.stereo.label, '立体声');
      expect(AudioChannels.reverseStereo.label, '反向立体声');
    });

    test('byName 反查与默认回退', () {
      expect(AudioChannels.byName('auto'), AudioChannels.auto);
      expect(AudioChannels.byName('reverseStereo'), AudioChannels.reverseStereo);
      expect(AudioChannels.byName(null), AudioChannels.autoSafe);
      expect(AudioChannels.byName('nope'), AudioChannels.autoSafe);
    });
  });

  group('isSupportedAudioFile', () {
    test('常见音频扩展名（大小写不敏感）', () {
      expect(isSupportedAudioFile('a.mp3'), isTrue);
      expect(isSupportedAudioFile('b.M4A'), isTrue);
      expect(isSupportedAudioFile('c.flac'), isTrue);
      expect(isSupportedAudioFile('d.opus'), isTrue);
      expect(isSupportedAudioFile('e.wav'), isTrue);
      expect(isSupportedAudioFile('f.ac3'), isTrue);
      expect(isSupportedAudioFile('g.dts'), isTrue);
    });

    test('非音频扩展名 / 无扩展名 / 点结尾', () {
      expect(isSupportedAudioFile('a.mp4'), isFalse);
      expect(isSupportedAudioFile('a.mkv'), isFalse);
      expect(isSupportedAudioFile('a.srt'), isFalse);
      expect(isSupportedAudioFile('noext'), isFalse);
      expect(isSupportedAudioFile('trailing.'), isFalse);
    });
  });

  group('audioChannelsPropertyValue', () {
    test('普通声道直接映射 mpv 值', () {
      expect(audioChannelsPropertyValue(AudioChannels.auto), 'auto');
      expect(audioChannelsPropertyValue(AudioChannels.autoSafe), 'auto-safe');
      expect(audioChannelsPropertyValue(AudioChannels.mono), 'mono');
      expect(audioChannelsPropertyValue(AudioChannels.stereo), 'stereo');
    });

    test('反向立体声重置为 auto-safe（用 af 交换左右）', () {
      expect(audioChannelsPropertyValue(AudioChannels.reverseStereo), 'auto-safe');
    });
  });

  group('buildAudioFilterChain', () {
    test('全部关闭 → 空串（清除滤镜链）', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
        ),
        '',
      );
    });

    test('动态范围压缩', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: true,
        ),
        'lavfi=[acompressor=threshold=-20dB:ratio=4:attack=5:release=50:makeup=2]',
      );
    });

    test('音量标准化', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: true,
          drc: false,
        ),
        'dynaudnorm',
      );
    });

    test('反向立体声 → pan 滤镜', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.reverseStereo,
          volumeNormalization: false,
          drc: false,
        ),
        'pan=[stereo|c0=c1|c1=c0]',
      );
    });

    test('三项叠加顺序：DRC → 音量标准化 → 反向立体声', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.reverseStereo,
          volumeNormalization: true,
          drc: true,
        ),
        'lavfi=[acompressor=threshold=-20dB:ratio=4:attack=5:release=50:makeup=2],'
        'dynaudnorm,'
        'pan=[stereo|c0=c1|c1=c0]',
      );
    });
  });

  group('audioTrackLabel', () {
    test('内嵌音轨：标题 + 格式', () {
      expect(
        audioTrackLabel(const AudioTrack(id: '1', title: '国语', codec: 'aac')),
        '国语 · aac',
      );
    });

    test('外挂音轨：标题 + 外挂 + 格式', () {
      expect(
        audioTrackLabel(
          const AudioTrack(
            id: '2',
            title: 'bgm.m4a',
            external: true,
            codec: 'aac',
          ),
        ),
        'bgm.m4a · 外挂 · aac',
      );
    });

    test('无标题无语言：回退「音轨 N」', () {
      expect(audioTrackLabel(const AudioTrack(id: '5')), '音轨 5');
    });
  });
}
