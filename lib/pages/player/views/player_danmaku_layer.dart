/// 弹幕渲染层：canvas_danmaku `DanmakuScreen` 的页面挂载封装。
///
/// 放入播放页 Stack 的视频层与手势层之间（DanmakuScreen 内部自带
/// `IgnorePointer`，不拦截任何手势）；`createdController` 回调把渲染
/// 控制器注册进业务层 [DanmakuController]（挂载即应用倍速/暂停状态），
/// 卸载时注销——横竖屏两个页面各挂一份，切换屏幕时无需清屏重启。
library;

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:moumou/services/danmaku_service.dart';

class PlayerDanmakuLayer extends StatefulWidget {
  /// 业务控制器（横竖屏页共享同一实例）
  final DanmakuController controller;

  const PlayerDanmakuLayer({super.key, required this.controller});

  @override
  State<PlayerDanmakuLayer> createState() => _PlayerDanmakuLayerState();
}

class _PlayerDanmakuLayerState extends State<PlayerDanmakuLayer> {
  canvas.DanmakuController<void>? _layer;

  @override
  Widget build(BuildContext context) {
    return canvas.DanmakuScreen<void>(
      createdController: (layer) {
        _layer = layer;
        widget.controller.attachLayer(layer);
      },
      // 阶段1：弹幕样式与各项配置全部使用默认值（倍速跟随由控制器
      // 通过 updateOption 动态应用，见 danmaku_service.dart）
      option: const canvas.DanmakuOption(),
    );
  }

  @override
  void dispose() {
    // 竖屏页 pop / 播放页退出时注销渲染层（业务控制器由页面统一销毁）
    final layer = _layer;
    if (layer != null) widget.controller.detachLayer(layer);
    _layer = null;
    super.dispose();
  }
}
