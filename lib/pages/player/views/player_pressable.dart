/// 播放器控制按钮统一点击反馈包装（横竖屏共用）：
/// 标准 Material 水波纹（InkWell）。
library;

import 'package:flutter/material.dart';

/// 播放页控制按钮的包装：用标准 [InkWell] 水波纹提供点击反馈，
/// 对齐 Kazumi 参考项目的做法（普通 IconButton / 默认 Material 反馈）。
class PlayerPressable extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  /// 水波纹形状（默认圆形，匹配图标按钮）
  final BorderRadius borderRadius;

  const PlayerPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: child,
    );
  }
}
