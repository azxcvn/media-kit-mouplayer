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

    test('均衡器全平（eqEnabled=true 但全 0）不追加滤镜', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
          eqEnabled: true,
          eqBands: const [0, 0, 0, 0, 0],
        ),
        '',
      );
    });

    test('均衡器启用 → 命名滤镜 @eq 追加在已有链之后', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
          eqEnabled: true,
          eqBands: const [4, 1, -1, 3, 5],
        ),
        '@eq:lavfi=[equalizer=f=60:t=o:w=2:g=4,'
        'equalizer=f=230:t=o:w=2:g=1,'
        'equalizer=f=910:t=o:w=2:g=-1,'
        'equalizer=f=3600:t=o:w=2:g=3,'
        'equalizer=f=14000:t=o:w=2:g=5]',
      );
    });

    test('低音增强 → @bass lowshelf，增益 = 0-100 × 0.2 dB', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
          eqEnabled: true,
          bassBoost: 50,
        ),
        '@bass:lavfi=[lowshelf=f=250:t=s:g=10]',
      );
    });

    test('虚拟环绕 → @virt extrastereo，强度 = 0-100 / 50', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
          eqEnabled: true,
          virtualizer: 100,
        ),
        '@virt:lavfi=[extrastereo=m=2]',
      );
    });

    test('均衡器 + 低音 + 虚拟环绕按顺序追加', () {
      expect(
        buildAudioFilterChain(
          channels: AudioChannels.autoSafe,
          volumeNormalization: false,
          drc: false,
          eqEnabled: true,
          eqBands: const [0, 0, 0, 0, 5],
          bassBoost: 50,
          virtualizer: 50,
        ),
        '@eq:lavfi=[equalizer=f=60:t=o:w=2:g=0,'
        'equalizer=f=230:t=o:w=2:g=0,'
        'equalizer=f=910:t=o:w=2:g=0,'
        'equalizer=f=3600:t=o:w=2:g=0,'
        'equalizer=f=14000:t=o:w=2:g=5],'
        '@bass:lavfi=[lowshelf=f=250:t=s:g=10],'
        '@virt:lavfi=[extrastereo=m=1]',
      );
    });
  });

  group('buildEqualizerLavfi', () {
    test('5 段 octave equalizer 链（与小喵 player 参数一致）', () {
      expect(
        buildEqualizerLavfi(const [0, 0, 0, 0, 0]),
        'lavfi=[equalizer=f=60:t=o:w=2:g=0,'
        'equalizer=f=230:t=o:w=2:g=0,'
        'equalizer=f=910:t=o:w=2:g=0,'
        'equalizer=f=3600:t=o:w=2:g=0,'
        'equalizer=f=14000:t=o:w=2:g=0]',
      );
    });

    test('增益数值去掉多余尾零（5.0 → 5，1.50 → 1.5）', () {
      expect(
        buildEqualizerLavfi(const [5.0, -2.0, 1.5, 0, 2.25]),
        'lavfi=[equalizer=f=60:t=o:w=2:g=5,'
        'equalizer=f=230:t=o:w=2:g=-2,'
        'equalizer=f=910:t=o:w=2:g=1.5,'
        'equalizer=f=3600:t=o:w=2:g=0,'
        'equalizer=f=14000:t=o:w=2:g=2.25]',
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
