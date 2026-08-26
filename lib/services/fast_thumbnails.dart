import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/foundation.dart';

/// 快速进度条缩略图引擎（FFI 直连自建 libmpv.so 内核中的 mk_thumbnail_*）。
///
/// 内核来源：https://github.com/azxcvn/libmpv-android-video-build
/// （mk-thumbnail 分支，补丁 mk_thumbnail.patch，接口声明见 mpv libmpv/client.h）
///
 /// 工作方式与 mpvRx 的 FastThumbnails 相同：独立 FFmpeg 解码器实例，
/// 与播放内核完全并行；MediaCodec 硬解优先，失败自动回退软解。
///
 /// JavaVM 已由 media_kit 启动时的 mpv_lavc_set_java_vm() 注册，无需额外初始化。
class FastThumbnails {
  FastThumbnails._();

  static DynamicLibrary? _lib;
  static bool _initialized = false;

  /// 自建内核是否可用（libmpv.so 中能找到 mk_thumbnail_grab 符号）。
  /// false = APK 里还是官方内核（没换 jar / 换错了）。
  static bool get isAvailable {
    if (!_initialized) {
      _initialized = true;
      if (Platform.isAndroid) {
        try {
          _lib = DynamicLibrary.open('libmpv.so');
          _lib!.lookupFunction<_GrabC, _GrabDart>('mk_thumbnail_grab');
        } catch (_) {
          _lib = null;
          debugPrint('[FastThumb] libmpv.so 中没有 mk_thumbnail_grab —— '
              '内核未替换为自建版本');
        }
      }
    }
    return _lib != null;
  }

  /// 抓取一帧缩略图，返回紧密排列的 RGBA8888 像素。
  ///
  /// [path] 本地视频绝对路径；[positionSec] 秒（0 = 首帧）；
  /// [dimension] 输出图像最长边像素；[useHwdec] MediaCodec 硬解（失败自动软解）。
  /// 返回 [GrabOutcome]：[frame] 为 null 表示没抓到图（不抛异常）；
  /// [stale] 为 true 表示请求被更新的请求顶掉（被抢占，非真实失败）。
  ///
  /// 调度（对齐 mpvRx）：最多 1 个解码在跑 + 1 个待跑；拖动时新请求
  /// 直接顶掉旧的待跑请求（旧帧对预览无价值），被顶掉的以 stale=true 完成。
  /// 任何时刻最多占用一个核，不会与播放内核抢 CPU。
  static Future<GrabOutcome> grab(
    String path,
    double positionSec, {
    int dimension = 320,
    bool useHwdec = true,
  }) async {
    if (!isAvailable) return (frame: null, stale: false);
    if (positionSec.isNaN || positionSec < 0) positionSec = 0;
    if (dimension <= 0 || dimension > 4096) dimension = 320;

    final job = _GrabJob(
      path: path,
      positionSec: positionSec,
      dimension: dimension,
      useHwdec: useHwdec ? 1 : 0,
    );
    // 新请求顶掉旧的待跑请求（其 future 以 stale=true 完成，表示「被抢占」，
    // 与真实解码失败区分开，供上层决定是否记录失败冷却）
    final stale = _waiting;
    _waiting = job;
    stale?._complete((frame: null, stale: true));
    _pump();
    return job.completer.future;
  }

  static _GrabJob? _running;
  static _GrabJob? _waiting;

  static void _pump() {
    while (_running == null && _waiting != null) {
      final job = _waiting!;
      _waiting = null;
      _running = job;
      _runGrab(job.path, job.positionSec, job.dimension, job.useHwdec)
          .then((frame) => job._complete((frame: frame, stale: false)))
          .catchError((Object e) {
        debugPrint('[FastThumb] grab error: $e');
        job._complete((frame: null, stale: false));
      }).whenComplete(() {
        _running = null;
        _pump();
      });
    }
  }

  /// 在子 isolate 执行抓帧。必须是**独立静态函数**：Isolate.run 的闭包会
  /// 连同捕获上下文一起发送，若与捕获了 _GrabJob（含 Completer，不可
  /// 发送）的兄弟闭包共享作用域，编译器合并上下文后整包不可发送
  /// （release AOT 实测踩坑：Context num_variables 会带上 _GrabJob）。
  static Future<FastThumbFrame?> _runGrab(
      String path, double positionSec, int dimension, int useHwdec) {
    return Isolate.run(() => _grabSync(path, positionSec, dimension, useHwdec));
  }

  /// [grab] 的便捷版本：直接返回可显示的 [ui.Image]。
  static Future<ui.Image?> grabImage(
    String path,
    double positionSec, {
    int dimension = 320,
    bool useHwdec = true,
  }) async {
    final out = await grab(path, positionSec,
        dimension: dimension, useHwdec: useHwdec);
    final frame = out.frame;
    if (frame == null) return null;

    final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final info = await codec.getNextFrame();
    return info.image;
  }

  /// 清空内核里的 MediaCodec 硬解上下文缓存（低内存时可选调用）。
  static void clearNativeCache() {
    if (!isAvailable) return;
    try {
      _lib!.lookupFunction<Void Function(), void Function()>(
          'mk_thumbnail_clear_cache')();
    } catch (_) {}
  }

  // ---- native 调用（跑在独立 Isolate 中，静态变量不跨 isolate 共享，
  //      库必须在本 isolate 内打开）----

  static FastThumbFrame? _grabSync(
      String path, double positionSec, int dimension, int useHwdec) {
    final lib = DynamicLibrary.open('libmpv.so');
    final grab = lib.lookupFunction<_GrabC, _GrabDart>('mk_thumbnail_grab');
    final free = lib.lookupFunction<_FreeC, _FreeDart>('mk_thumbnail_free');

    final units = utf8.encode(path);
    final pathPtr = malloc<Uint8>(units.length + 1);
    pathPtr.asTypedList(units.length + 1)
      ..setRange(0, units.length, units)
      ..[units.length] = 0;

    final outData = malloc<Pointer<Uint8>>();
    final outWidth = malloc<Int32>();
    final outHeight = malloc<Int32>();

    FastThumbFrame? result;
    final rc = grab(pathPtr, positionSec, dimension, useHwdec,
        outData, outWidth, outHeight);
    if (rc == 0) {
      final w = outWidth.value;
      final h = outHeight.value;
      final data = outData.value;
      if (data != nullptr && w > 0 && h > 0) {
        // 拷贝到 Dart 堆后立刻释放 native 缓冲
        final bytes = Uint8List.fromList(data.asTypedList(w * h * 4));
        result = FastThumbFrame(bytes, w, h);
      }
      free(data);
    }

    malloc.free(outHeight);
    malloc.free(outWidth);
    malloc.free(outData);
    malloc.free(pathPtr);
    return result;
  }
}

/// 一帧缩略图：RGBA8888 紧密像素 + 尺寸。
class FastThumbFrame {
  const FastThumbFrame(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// 抓帧结果：[frame] 为 null 表示没抓到图；[stale] 为 true 表示请求被更新的
/// 请求顶掉（被抢占，而非真实解码失败），供上层区分是否记录失败冷却。
typedef GrabOutcome = ({FastThumbFrame? frame, bool stale});

/// 一次抓帧请求（单飞队列的节点）。
class _GrabJob {
  _GrabJob({
    required this.path,
    required this.positionSec,
    required this.dimension,
    required this.useHwdec,
  });

  final String path;
  final double positionSec;
  final int dimension;
  final int useHwdec;
  final completer = Completer<GrabOutcome>();
  bool _done = false;

  void _complete(GrabOutcome outcome) {
    if (_done) return;
    _done = true;
    completer.complete(outcome);
  }
}

typedef _GrabC = Int32 Function(
    Pointer<Uint8> path,
    Double position,
    Int32 dimension,
    Int32 useHwdec,
    Pointer<Pointer<Uint8>> outData,
    Pointer<Int32> outWidth,
    Pointer<Int32> outHeight);
typedef _GrabDart = int Function(
    Pointer<Uint8> path,
    double position,
    int dimension,
    int useHwdec,
    Pointer<Pointer<Uint8>> outData,
    Pointer<Int32> outWidth,
    Pointer<Int32> outHeight);
typedef _FreeC = Void Function(Pointer<Uint8> data);
typedef _FreeDart = void Function(Pointer<Uint8> data);
