import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/formatters.dart';

void main() {
  group('formatNetworkSpeed（工作.md 阶段1 第 1 点：自动切换 KB/MB，两位小数）', () {
    test('非正值归零显示', () {
      expect(formatNetworkSpeed(0), '0.00 KB/s');
      expect(formatNetworkSpeed(-100), '0.00 KB/s');
    });

    test('小于 1024 KB/s 显示 KB', () {
      // 102400 B/s = 100 KB/s
      expect(formatNetworkSpeed(102400), '100.00 KB/s');
      // 1587.2 KB/s 以下（1625292.8 B/s = 1587.2 KB/s）
      expect(formatNetworkSpeed(525312), '513.00 KB/s'); // 525312/1024 = 513
    });

    test('达到 1024 KB/s 切换为 MB', () {
      // 1048576 B/s = 1024 KB/s = 1.00 MB/s
      expect(formatNetworkSpeed(1048576), '1.00 MB/s');
      // 2.5 MB/s = 2621440 B/s
      expect(formatNetworkSpeed(2621440), '2.50 MB/s');
    });

    test('保留两位小数', () {
      // 1.234567 MB/s = 1294525.5 B/s（约）
      expect(formatNetworkSpeed(1294525), '1.23 MB/s');
    });
  });

  group('isOnlineMedia（网速详情仅在线播放显示）', () {
    test('本地路径返回 false', () {
      expect(isOnlineMedia('/storage/emulated/0/Video/a.mp4'), isFalse);
      expect(isOnlineMedia('file:///sdcard/b.mkv'), isFalse);
      expect(isOnlineMedia(''), isFalse);
    });

    test('网络协议返回 true', () {
      expect(isOnlineMedia('http://example.com/v.mp4'), isTrue);
      expect(isOnlineMedia('https://example.com/v.m3u8'), isTrue);
      expect(isOnlineMedia('rtmp://live.example.com/stream'), isTrue);
      expect(isOnlineMedia('rtsp://192.168.1.1/feed'), isTrue);
    });

    test('协议大小写不敏感', () {
      expect(isOnlineMedia('HTTP://EXAMPLE.COM/v.mp4'), isTrue);
      expect(isOnlineMedia('Https://example.com'), isTrue);
    });
  });
}
