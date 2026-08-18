import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:moumou/utils/formatters.dart';

/// 进度条拖动时的缩略图预览气泡（对齐 kt 项目 `SeekbarThumbnailPreview`）：
/// 16:9 预览图（宽 160）+ 下方时间胶囊，水平位置跟随拖动比例。
///
/// 图片字节来自 [DeviceServices.getVideoFrameAt]（本地视频任意时刻抓帧，
/// 原生 MediaMetadataRetriever + 双层缓存）。[visible] 控制淡入淡出。
class PlayerThumbnailPreview extends StatelessWidget {
  /// 预览图 JPEG 字节（null 时显示加载占位）
  final Uint8List? bytes;

  /// 预览时间点
  final Duration time;

  /// 拖动进度比例 0 – 1
  final double fraction;

  /// 是否显示（拖动中显示，松手淡出）
  final bool visible;

  const PlayerThumbnailPreview({
    super.key,
    required this.bytes,
    required this.time,
    required this.fraction,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const previewWidth = 160.0;
            final left = (constraints.maxWidth - previewWidth)
                .clamp(0.0, double.infinity) *
                fraction.clamp(0.0, 1.0);
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(left: left),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 16:9 预览图
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: previewWidth,
                        height: previewWidth * 9 / 16,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          color: Colors.black.withValues(alpha: 0.72),
                        ),
                        child: bytes != null
                            ? Image.memory(
                                bytes!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // 时间胶囊
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        formatDuration(time.inMilliseconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
