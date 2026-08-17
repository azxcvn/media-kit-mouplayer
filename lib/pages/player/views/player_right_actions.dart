import 'package:flutter/material.dart';

/// 播放页右侧竖排操作按钮：截图 + 锁定（对齐 Kazumi 的左侧控制栏布局）。
///
/// 两个按钮**固定自带「矩形圆角灰黑色背景」**（Colors.black45 + 圆角 12），
/// 不受设置内「按钮背景」选项控制 —— 该选项只作用于顶栏/底栏图标。
class PlayerRightActions extends StatelessWidget {
  final bool locked;
  final VoidCallback onScreenshot;
  final VoidCallback onToggleLock;

  const PlayerRightActions({
    super.key,
    required this.locked,
    required this.onScreenshot,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 截图（锁定后隐藏，避免误触）
        if (!locked) ...[
          _FixedBackgroundButton(
            icon: Icons.photo_camera_outlined,
            tooltip: '截图',
            onPressed: onScreenshot,
          ),
          const SizedBox(height: 12),
        ],
        _FixedBackgroundButton(
          icon: locked ? Icons.lock_outline : Icons.lock_open,
          tooltip: locked ? '解锁' : '锁定',
          onPressed: onToggleLock,
        ),
      ],
    );
  }
}

/// 固定灰黑圆角背景的圆形按钮（截图/锁定专用）
class _FixedBackgroundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _FixedBackgroundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
