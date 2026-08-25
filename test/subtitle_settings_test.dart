import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/subtitle_track.dart';
import 'package:moumou/services/subtitle_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SubtitleSettings.instance.reset();
  });

  test('默认值（工作.md 阶段1 第 3 点）', () {
    final s = SubtitleSettings.instance;
    expect(s.delay, 0);
    expect(s.scale, 1.0);
    expect(s.position, 100);
    expect(s.align, SubtitleAlign.center);
    expect(s.color, '#FFFFFF');
    expect(s.font, 'auto');
    expect(s.fontSourceDir, '');
    // 默认尊重内嵌字幕自带样式与字体
    expect(s.overrideEmbeddedStyle, isFalse);
  });

  test('字幕延迟：设置/持久化/±60 范围钳制/快捷叠加', () async {
    final s = SubtitleSettings.instance;
    await s.setDelay(1.5);
    expect(s.delay, 1.5);
    await s.load(); // 模拟重启
    expect(s.delay, 1.5);
    // 快捷叠加：+0.5 → 2.0；-1.0 → 1.0
    await s.adjustDelay(0.5);
    expect(s.delay, 2.0);
    await s.adjustDelay(-1.0);
    expect(s.delay, 1.0);
    // 范围钳制 -60 ~ +60
    await s.adjustDelay(999);
    expect(s.delay, SubtitleSettings.maxDelay);
    await s.adjustDelay(-999);
    expect(s.delay, SubtitleSettings.minDelay);
  });

  test('字幕样式：大小/颜色/内嵌样式覆盖持久化', () async {
    final s = SubtitleSettings.instance;
    await s.setScale(1.8);
    await s.setColor('#FFEB3B');
    await s.setOverrideEmbeddedStyle(true);
    await s.load();
    expect(s.scale, 1.8);
    expect(s.color, '#FFEB3B');
    expect(s.overrideEmbeddedStyle, isTrue);
    // 大小范围钳制 0.5 – 3.0
    await s.setScale(0.1);
    expect(s.scale, SubtitleSettings.minScale);
    await s.setScale(9.9);
    expect(s.scale, SubtitleSettings.maxScale);
  });

  test('字幕杂项：垂直位置/水平对齐持久化', () async {
    final s = SubtitleSettings.instance;
    await s.setPosition(70);
    await s.setAlign(SubtitleAlign.left);
    await s.load();
    expect(s.position, 70);
    expect(s.align, SubtitleAlign.left);
    // 位置范围钳制 0 – 100
    await s.setPosition(-10);
    expect(s.position, SubtitleSettings.minPos);
    await s.setPosition(999);
    expect(s.position, SubtitleSettings.maxPos);
  });

  test('字幕字体：默认 auto 跟随系统字库 /system/fonts', () async {
    final s = SubtitleSettings.instance;
    expect(s.font, 'auto');
    await s.setFont('auto', '');
    expect(s.font, 'auto');
  });

  test('字体源目录：设置/持久化/清除（工作.md 第 1 点：目录选择记忆）', () async {
    final s = SubtitleSettings.instance;
    expect(s.fontSourceDir, '');
    const uri =
        'content://com.android.externalstorage.documents/tree/primary%3AFonts';
    await s.setFontSourceDir(uri);
    expect(s.fontSourceDir, uri);
    await s.load(); // 模拟重启
    expect(s.fontSourceDir, uri);
    await s.setFontSourceDir(''); // 清除目录
    expect(s.fontSourceDir, '');
    await s.load();
    expect(s.fontSourceDir, '');
  });

  test('描边模式：默认无，设置后持久化', () async {
    final s = SubtitleSettings.instance;
    expect(s.borderStyle, SubtitleBorderStyle.none);
    await s.setBorderStyle(SubtitleBorderStyle.outline);
    expect(s.borderStyle, SubtitleBorderStyle.outline);
    await s.load();
    expect(s.borderStyle, SubtitleBorderStyle.outline);
    await s.setBorderStyle(SubtitleBorderStyle.box);
    expect(s.borderStyle, SubtitleBorderStyle.box);
  });

  test('外挂字幕记忆：添加/去重/移除/持久化', () async {
    final s = SubtitleSettings.instance;
    expect(s.importedSubtitlePaths, isEmpty);
    await s.addImportedSubtitle('/a/1.srt');
    await s.addImportedSubtitle('/a/1.srt'); // 去重
    await s.addImportedSubtitle('/a/2.ass');
    expect(s.importedSubtitlePaths, ['/a/1.srt', '/a/2.ass']);
    await s.load(); // 模拟重启
    expect(s.importedSubtitlePaths, ['/a/1.srt', '/a/2.ass']);
    await s.removeImportedSubtitle('/a/1.srt');
    expect(s.importedSubtitlePaths, ['/a/2.ass']);
  });

  test('按视频独立外挂字幕记忆与选中轨道：添加/去重/移除/持久化', () async {
    final s = SubtitleSettings.instance;
    const videoA = '/storage/emulated/0/Movies/A.mp4';
    const videoB = '/storage/emulated/0/Movies/B.mp4';

    expect(s.getImportedSubtitlesFor(videoA), isEmpty);
    expect(s.getImportedSubtitlesFor(videoB), isEmpty);

    // 为 A 视频添加外挂字幕
    await s.addImportedSubtitleFor(videoA, '/a/1.srt');
    await s.addImportedSubtitleFor(videoA, '/a/1.srt'); // 去重
    await s.addImportedSubtitleFor(videoA, '/a/2.ass');
    await s.setSelectedSubtitleFor(videoA, '/a/2.ass');

    // 为 B 视频添加外挂字幕
    await s.addImportedSubtitleFor(videoB, '/b/sub.vtt');
    await s.setSelectedSubtitleFor(videoB, 'track_1');

    expect(s.getImportedSubtitlesFor(videoA), ['/a/1.srt', '/a/2.ass']);
    expect(s.getSelectedSubtitleFor(videoA), '/a/2.ass');
    expect(s.getImportedSubtitlesFor(videoB), ['/b/sub.vtt']);
    expect(s.getSelectedSubtitleFor(videoB), 'track_1');

    // 模拟重启持久化加载
    await s.load();
    expect(s.getImportedSubtitlesFor(videoA), ['/a/1.srt', '/a/2.ass']);
    expect(s.getSelectedSubtitleFor(videoA), '/a/2.ass');
    expect(s.getImportedSubtitlesFor(videoB), ['/b/sub.vtt']);
    expect(s.getSelectedSubtitleFor(videoB), 'track_1');

    // 移除 A 视频某一条字幕
    await s.removeImportedSubtitleFor(videoA, '/a/2.ass');
    expect(s.getImportedSubtitlesFor(videoA), ['/a/1.srt']);
    expect(s.getSelectedSubtitleFor(videoA), isNull); // 选中的字幕被删除后清除选中记忆
  });

  test('重置所有样式：颜色/描边/效果回默认，保留延迟/缩放/位置/字体以及强制覆盖内嵌样式开关', () async {
    final s = SubtitleSettings.instance;
    await s.setDelay(3);
    await s.setScale(1.5);
    await s.setPosition(80);
    await s.setFont('myFont', '/data/fonts');
    await s.setColor('#FF0000');
    await s.setBorderColor('#00FF00');
    await s.setBorderStyle(SubtitleBorderStyle.outline);
    await s.setBorderSize(6);
    await s.setBold(true);
    await s.setOverrideEmbeddedStyle(true);
    await s.resetStyles();
    expect(s.color, '#FFFFFF');
    expect(s.borderColor, isNull);
    expect(s.borderStyle, SubtitleBorderStyle.none);
    expect(s.borderSize, 2.5);
    expect(s.bold, isFalse);
    // 强制覆盖开关保持原选择（不被强制重置）
    expect(s.overrideEmbeddedStyle, isTrue);
    // 不重置的部分保留
    expect(s.delay, 3);
    expect(s.scale, 1.5);
    expect(s.position, 80);
    expect(s.font, 'myFont');
    await s.load(); // 持久化一致
    expect(s.color, '#FFFFFF');
    expect(s.borderColor, isNull);
    expect(s.overrideEmbeddedStyle, isTrue);
  });
}
