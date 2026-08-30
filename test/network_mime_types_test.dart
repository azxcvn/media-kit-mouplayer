import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/network_mime_types.dart';

void main() {
  test('isNetworkVideoFile 识别视频扩展名', () {
    expect(isNetworkVideoFile('a.mp4'), isTrue);
    expect(isNetworkVideoFile('a.MKV'), isTrue);
    expect(isNetworkVideoFile('a.m2ts'), isTrue);
    expect(isNetworkVideoFile('a.webm'), isTrue);
    expect(isNetworkVideoFile('a.ts'), isTrue);
  });

  test('isNetworkVideoFile 拒绝非视频文件', () {
    expect(isNetworkVideoFile('a.srt'), isFalse);
    expect(isNetworkVideoFile('a.ass'), isFalse);
    expect(isNetworkVideoFile('a.mp3'), isFalse);
    expect(isNetworkVideoFile('a.txt'), isFalse);
    expect(isNetworkVideoFile('a.flac'), isFalse);
    expect(isNetworkVideoFile('README'), isFalse);
  });

  test('networkMimeTypeForFileName 常见映射', () {
    expect(networkMimeTypeForFileName('a.mp4'), 'video/mp4');
    expect(networkMimeTypeForFileName('a.mkv'), 'video/x-matroska');
    expect(networkMimeTypeForFileName('a.m3u8'), 'application/vnd.apple.mpegurl');
    expect(networkMimeTypeForFileName('a.flac'), 'audio/*');
    expect(networkMimeTypeForFileName('a.unknownext'), isNull);
  });
}