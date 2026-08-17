import 'package:flutter/material.dart';

/// 双击手势模式（可在「播放器设置」中自定义）
enum DoubleTapMode {
  pause('双击暂停/播放'),
  seek('双击左退右进'),
  mixed('混合（中央暂停，两侧进退）');

  final String label;
  const DoubleTapMode(this.label);
}

/// 画面比例（对齐 PiliPlus 的 VideoFitType）：
/// 通过 Video 组件的 [BoxFit] 与 [aspectRatio] 实现，无需 mpv 属性。
enum PlayerVideoFit {
  fill('拉伸', BoxFit.fill, null),
  contain('自动', BoxFit.contain, null),
  cover('裁剪', BoxFit.cover, null),
  fitWidth('等宽', BoxFit.fitWidth, null),
  fitHeight('等高', BoxFit.fitHeight, null),
  none('原始', BoxFit.none, null),
  scaleDown('限制', BoxFit.scaleDown, null),
  ratio4x3('4:3', BoxFit.contain, 4 / 3),
  ratio16x9('16:9', BoxFit.contain, 16 / 9);

  const PlayerVideoFit(this.label, this.boxFit, this.aspectRatio);

  /// 面板展示名
  final String label;

  /// Video 组件的缩放方式
  final BoxFit boxFit;

  /// 固定宽高比（4:3 / 16:9），其余为 null
  final double? aspectRatio;
}

/// 播放器右上角可自定义的按钮动作（最多 5 个，顺序可调）。
///
/// [implemented] 为 false 的动作是占位入口（字幕/弹幕/音轨），
/// 顶栏点击提示「功能即将上线」，待后续接入具体功能。
///
/// 注意：倍速（speed）**不在**顶栏动作之列 —— 倍速按钮固定于播放页
/// 底栏（超分辨率按钮左侧），不支持在顶栏控制栏增加或删除。
enum PlayerTopAction {
  subtitle('subtitle', '字幕', Icons.subtitles_outlined, false),
  danmaku('danmaku', '弹幕', Icons.comment_outlined, false),
  audio('audio', '音轨', Icons.library_music_outlined, false),
  aspect('aspect', '比例', Icons.aspect_ratio, true);

  /// 持久化标识（稳定，勿改）
  final String id;
  final String label;
  final IconData icon;

  /// 是否已实现具体功能（false = 占位入口，待接入）
  final bool implemented;

  const PlayerTopAction(this.id, this.label, this.icon, this.implemented);

  /// 按持久化 id 反查动作（找不到返回 null）
  static PlayerTopAction? byId(String? id) {
    if (id == null) return null;
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}
