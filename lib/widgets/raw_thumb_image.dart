import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:moumou/services/fast_thumbnails.dart';

/// 直接渲染 [FastThumbFrame] 的 RGBA 像素（无 PNG/JPEG 编码往返）。
///
/// 帧切换时异步解码新 [ui.Image]，解码完成前保持上一帧（无缝过渡）；
/// 旧 [ui.Image] 在替换后释放。宽高比由 [frame] 自带，配合 [fit] 拉伸。
class RawThumbImage extends StatefulWidget {
  const RawThumbImage({super.key, required this.frame, this.fit});

  final FastThumbFrame frame;

  /// null 时按原始尺寸显示；一般传 BoxFit.cover
  final BoxFit? fit;

  @override
  State<RawThumbImage> createState() => _RawThumbImageState();
}

class _RawThumbImageState extends State<RawThumbImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode(widget.frame);
  }

  @override
  void didUpdateWidget(RawThumbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同一帧对象（缓存命中/邻近帧复用）不重复解码
    if (oldWidget.frame != widget.frame) {
      _decode(widget.frame);
    }
  }

  void _decode(FastThumbFrame frame) {
    final frameId = frame;
    _decodeInto(frame).then((image) {
      if (!mounted || frameId != widget.frame) {
        image?.dispose();
        return;
      }
      final old = _image;
      _image = image;
      setState(() {});
      old?.dispose();
    });
  }

  static Future<ui.Image?> _decodeInto(FastThumbFrame frame) async {
    try {
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
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const SizedBox.shrink();
    }
    return RawImage(
      image: image,
      fit: widget.fit,
    );
  }
}
