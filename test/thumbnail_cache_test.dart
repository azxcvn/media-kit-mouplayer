import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/thumbnail_preload_service.dart';

void main() {
  setUp(() {
    DeviceServices.debugClearFrames();
  });

  group('ThumbnailPreloadService.intervalFor', () {
    test('长视频：间隔按目标帧数自适应（90 分钟 → 60 秒）', () {
      expect(
        ThumbnailPreloadService.intervalFor(const Duration(minutes: 90)),
        60000,
      );
    });

    test('中视频：10 分钟 → 10 秒', () {
      expect(
        ThumbnailPreloadService.intervalFor(const Duration(minutes: 10)),
        10000,
      );
    });

    test('短视频：2 分钟 → 5 秒（最短间隔 2 秒下限不越界）', () {
      expect(
        ThumbnailPreloadService.intervalFor(const Duration(minutes: 2)),
        5000,
      );
    });

    test('未知时长：返回默认 5 秒', () {
      expect(ThumbnailPreloadService.intervalFor(Duration.zero), 5000);
    });

    test('间隔与目标帧数一致性：间隔有界、帧数有界', () {
      for (final minutes in [1, 5, 30, 120]) {
        final duration = Duration(minutes: minutes);
        final interval = ThumbnailPreloadService.intervalFor(duration);
        // 间隔 2 – 60 秒
        expect(interval, inInclusiveRange(2000, 60000));
        final cells = duration.inMilliseconds / interval;
        // 短视频最少 ~12 帧，超长视频最多 ~120 帧
        expect(cells, lessThanOrEqualTo(120));
        expect(cells, greaterThanOrEqualTo(10));
      }
    });
  });

  group('DeviceServices 帧缓存查询', () {
    const path = '/storage/emulated/0/Movies/demo.mp4';

    test('peekFrame：精确秒桶命中', () {
      DeviceServices.debugPutFrame(path, 10500, Uint8List.fromList([1, 2, 3]));
      final bytes = DeviceServices.peekFrame(path, 10999); // 同一秒桶
      expect(bytes, isNotNull);
      expect(bytes!.length, 3);
    });

    test('peekFrame：不同秒桶不命中', () {
      DeviceServices.debugPutFrame(path, 10500, Uint8List.fromList([1]));
      expect(DeviceServices.peekFrame(path, 11000), isNull);
    });

    test('peekNearestFrame：返回间隔内最近帧', () {
      DeviceServices.debugPutFrame(path, 60000, Uint8List.fromList([1]));
      DeviceServices.debugPutFrame(path, 120000, Uint8List.fromList([2]));
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
      DeviceServices.debugPutFrame(path, 0, Uint8List.fromList([1]));
      expect(
        DeviceServices.peekNearestFrame(path, 60000, maxGapMs: 10000),
        isNull,
      );
    });

    test('peekNearestFrame：其他视频的帧不串扰', () {
      DeviceServices.debugPutFrame(path, 60000, Uint8List.fromList([1]));
      expect(
        DeviceServices.peekNearestFrame(
          '/storage/emulated/0/Movies/other.mp4',
          60000,
          maxGapMs: 10000,
        ),
        isNull,
      );
    });
  });

  test('预生成服务：isActiveFor / cancel 状态流转', () {
    final preload = ThumbnailPreloadService();
    expect(preload.isActiveFor('/a.mp4'), isFalse);

    // start 会 cancel 上一次，再置为新路径
    preload.start('/a.mp4', 600000, fromMs: 1000);
    expect(preload.isActiveFor('/a.mp4'), isTrue);

    preload.start('/b.mp4', 300000, fromMs: 0);
    expect(preload.isActiveFor('/a.mp4'), isFalse);
    expect(preload.isActiveFor('/b.mp4'), isTrue);

    preload.cancel();
    expect(preload.isActiveFor('/b.mp4'), isFalse);
  });
}
