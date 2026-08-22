import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/fast_thumbnails.dart';

FastThumbFrame _frame(int fill, [int width = 2, int height = 2]) =>
    FastThumbFrame(
      Uint8List.fromList(List.filled(width * height * 4, fill)),
      width,
      height,
    );

void main() {
  setUp(() {
    DeviceServices.debugClearFrames();
  });

  group('DeviceServices 帧缓存查询（FFmpeg 快速引擎，RGBA 直通）', () {
    const path = '/storage/emulated/0/Movies/demo.mp4';

    test('peekFrame：精确秒桶命中', () {
      DeviceServices.debugPutFrame(path, 10500, _frame(1, 2, 1));
      final frame = DeviceServices.peekFrame(path, 10999); // 同一秒桶
      expect(frame, isNotNull);
      expect(frame!.rgba.length, 2 * 1 * 4);
    });

    test('peekFrame：不同秒桶不命中', () {
      DeviceServices.debugPutFrame(path, 10500, _frame(1));
      expect(DeviceServices.peekFrame(path, 11000), isNull);
    });

    test('peekNearestFrame：返回间隔内最近帧', () {
      DeviceServices.debugPutFrame(path, 60000, _frame(1));
      DeviceServices.debugPutFrame(path, 120000, _frame(2));
      // 80s 距 60s（20s）比距 120s（40s）更近
      final nearest = DeviceServices.peekNearestFrame(
        path,
        80000,
        maxGapMs: 30000,
      );
      expect(nearest, isNotNull);
      expect(nearest!.bucketMs, 60000);
    });

    test('peekNearestFrame：超出间隔返回 null', () {
      DeviceServices.debugPutFrame(path, 0, _frame(1));
      expect(
        DeviceServices.peekNearestFrame(path, 60000, maxGapMs: 10000),
        isNull,
      );
    });

    test('peekNearestFrame：其他视频的帧不串扰', () {
      DeviceServices.debugPutFrame(path, 60000, _frame(1));
      expect(
        DeviceServices.peekNearestFrame(
          '/storage/emulated/0/Movies/other.mp4',
          60000,
          maxGapMs: 10000,
        ),
        isNull,
      );
    });

    test('LRU：超限（24MB）淘汰最久未用帧', () {
      // 每帧 1MB（512×512×4 字节），上限 24MB → 第 25 帧起触发淘汰
      final big = FastThumbFrame(
        Uint8List.fromList(List.filled(512 * 512 * 4, 7)),
        512,
        512,
      );
      // 先插入最早帧，再填满到超限（31MB），最早帧应被淘汰
      DeviceServices.debugPutFrame(path, 0, big);
      for (var b = 2000; b <= 60000; b += 2000) {
        DeviceServices.debugPutFrame(path, b, big);
      }
      expect(DeviceServices.peekFrame(path, 0), isNull);
      expect(DeviceServices.peekFrame(path, 60000), isNotNull);
    });
  });
}
