import 'package:flutter/material.dart';

/// 双击手势模式（可在「播放器设置」中自定义）
enum DoubleTapMode {
  pause('双击暂停/播放'),
  seek('双击左退右进'),
  mixed('混合（中央暂停，两侧进退）');

  final String label;
  const DoubleTapMode(this.label);
}

/// 播放器右上角可自定义的按钮动作（最多 5 个，顺序可调）。
///
/// [implemented] 为 false 的动作是占位入口（字幕/弹幕/音轨/比例），
/// 顶栏点击提示「功能即将上线」，待后续接入具体功能。
enum PlayerTopAction {
  speed('speed', '倍速', Icons.speed_rounded, true),
  subtitle('subtitle', '字幕', Icons.subtitles_outlined, false),
  danmaku('danmaku', '弹幕', Icons.comment_outlined, false),
  audio('audio', '音轨', Icons.library_music_outlined, false),
  aspect('aspect', '比例', Icons.aspect_ratio, false);

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
