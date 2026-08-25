import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/media_scan_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaScanSettings.instance.reset();
  });

  test('默认值校验', () {
    final s = MediaScanSettings.instance;
    expect(s.scanNoMedia, isFalse);
    expect(s.scanHiddenFolders, isFalse);
    expect(s.filterMode, FolderFilterMode.none);
    expect(s.blacklistFolders, isEmpty);
    expect(s.whitelistFolders, isEmpty);
  });

  test('切换 scanNoMedia 与 scanHiddenFolders 并持久化', () async {
    final s = MediaScanSettings.instance;
    await s.setScanNoMedia(true);
    await s.setScanHiddenFolders(true);
    expect(s.scanNoMedia, isTrue);
    expect(s.scanHiddenFolders, isTrue);

    // 模拟应用重启
    s.reset();
    await s.load();
    expect(s.scanNoMedia, isTrue);
    expect(s.scanHiddenFolders, isTrue);
  });

  test('切换 filterMode 并持久化', () async {
    final s = MediaScanSettings.instance;
    expect(s.filterMode, FolderFilterMode.none);

    await s.setFilterMode(FolderFilterMode.blacklist);
    expect(s.filterMode, FolderFilterMode.blacklist);

    s.reset();
    await s.load();
    expect(s.filterMode, FolderFilterMode.blacklist);

    await s.setFilterMode(FolderFilterMode.whitelist);
    expect(s.filterMode, FolderFilterMode.whitelist);
  });

  test('黑名单模式：添加、去重、移除与路径判定', () async {
    final s = MediaScanSettings.instance;
    await s.setFilterMode(FolderFilterMode.blacklist);

    await s.addBlacklistFolder('/storage/emulated/0/Movies/Secret');
    await s.addBlacklistFolder('/storage/emulated/0/Movies/Secret/'); // 去重
    await s.addBlacklistFolder('/storage/emulated/0/Download/Temp');

    expect(s.blacklistFolders, [
      '/storage/emulated/0/Movies/Secret',
      '/storage/emulated/0/Download/Temp',
    ]);

    // 判定黑名单命中与放行
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Secret/video.mp4'),
      isFalse,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Secret/Sub/video.mp4'),
      isFalse,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Download/Temp/1.mp4'),
      isFalse,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Public/video.mp4'),
      isTrue,
    );

    // 移除黑名单项
    await s.removeBlacklistFolder('/storage/emulated/0/Movies/Secret');
    expect(s.blacklistFolders, ['/storage/emulated/0/Download/Temp']);
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Secret/video.mp4'),
      isTrue,
    );
  });

  test('白名单模式：添加、去重、移除与路径判定', () async {
    final s = MediaScanSettings.instance;
    await s.setFilterMode(FolderFilterMode.whitelist);

    // 白名单为空时默认全部允许
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/video.mp4'),
      isTrue,
    );

    await s.addWhitelistFolder('/storage/emulated/0/Anime');
    await s.addWhitelistFolder('/storage/emulated/0/Movies');

    expect(s.whitelistFolders, [
      '/storage/emulated/0/Anime',
      '/storage/emulated/0/Movies',
    ]);

    // 白名单命中与未命中
    expect(
      s.isPathAllowed('/storage/emulated/0/Anime/Ep01.mp4'),
      isTrue,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Anime/Season1/Ep01.mp4'),
      isTrue,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Movie.mkv'),
      isTrue,
    );
    expect(
      s.isPathAllowed('/storage/emulated/0/Download/Other.mp4'),
      isFalse,
    );

    // 移除白名单项
    await s.removeWhitelistFolder('/storage/emulated/0/Anime');
    expect(s.whitelistFolders, ['/storage/emulated/0/Movies']);
    expect(
      s.isPathAllowed('/storage/emulated/0/Anime/Ep01.mp4'),
      isFalse,
    );
  });

  test('全部扫描模式下忽略黑白名单配置', () async {
    final s = MediaScanSettings.instance;
    await s.setFilterMode(FolderFilterMode.none);
    await s.addBlacklistFolder('/storage/emulated/0/Movies/Secret');

    expect(
      s.isPathAllowed('/storage/emulated/0/Movies/Secret/video.mp4'),
      isTrue,
    );
  });
}
