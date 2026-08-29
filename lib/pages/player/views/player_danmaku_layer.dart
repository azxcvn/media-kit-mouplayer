/// 弹幕渲染层：canvas_danmaku `DanmakuScreen` 的页面挂载封装。
///
/// 放入播放页 Stack 的视频层与手势层之间（DanmakuScreen 内部自带
/// `IgnorePointer`，不拦截任何手势）；`createdController` 回调把渲染
/// 控制器注册进业务层 [DanmakuController]（挂载即应用样式/配置/倍速/
/// 暂停状态），卸载时注销——横竖屏两个页面各挂一份，切换屏幕时无需
/// 清屏重启。
///
/// 阶段2：初始 [canvas.DanmakuOption] 从弹幕设置单例构建（新挂载层
/// 首帧即用户样式，不闪默认值）；后续变化由业务层订阅设置后经
/// `updateOption` 热更新下发。
library;

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:moumou/services/danmaku_service.dart';
import 'package:moumou/services/danmaku_settings.dart';

class PlayerDanmakuLayer extends StatefulWidget {
  /// 业务控制器（横竖屏页共享同一实例）
  final DanmakuController controller;

  const PlayerDanmakuLayer({super.key, required this.controller});

  @override
  State<PlayerDanmakuLayer> createState() => _PlayerDanmakuLayerState();
}

/// 弹幕设置 → canvas DanmakuOption 的映射统一收敛在 danmaku_service.dart
/// （[danmakuOptionFromSettings]），此处只做挂载/卸载与初始选项下发，避免
/// 两份映射漂移。

class _PlayerDanmakuLayerState extends State<PlayerDanmakuLayer> {
  canvas.DanmakuController<void>? _layer;

  @override
  Widget build(BuildContext context) {
    return canvas.DanmakuScreen<void>(
      createdController: (layer) {
        _layer = layer;
        widget.controller.attachLayer(layer);
      },
      // 初始值取当前设置（新挂载层首帧即用户样式）；后续变化由业务层
      // updateOption 热更新（倍速/速度/样式/配置统一走 danmaku_service）
      option: danmakuOptionFromSettings(DanmakuSettings.instance),
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
