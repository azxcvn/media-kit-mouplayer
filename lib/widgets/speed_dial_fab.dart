import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 右下角 FAB 的底部额外抬升量（相对 Scaffold 默认 endFloat 的 16dp 底距）。
///
/// 悬浮胶囊导航栏（CapsuleNavBar）高 64 + 底部间距 8，顶缘距内容底 72；
/// 再抬 64 使 FAB 底缘距底 80，即「略高于」导航栏顶缘约 8dp。
/// 仅主页速拨按钮使用（网络存储页无底部导航栏，用标准 endFloat 位置）。
const double kFabLiftAboveNav = 64;

/// 悬浮速拨菜单项
class SpeedDialAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SpeedDialAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// 悬浮速拨按钮：右下角主按钮点击后向上展开若干带文字的选项（纵向）。
///
/// 展开/收起由内部 [AnimationController] 驱动：主按钮「+」旋转 45° 变「×」，
/// 选项从下方淡入上浮。再次点击主按钮或选中任一选项即收起。
class SpeedDialFab extends StatefulWidget {
  final List<SpeedDialAction> actions;

  /// 用于避免多个页面间 FAB 的 Hero 动画冲突（不同页面传不同值）。
  final Object heroTag;

  const SpeedDialFab({
    super.key,
    required this.actions,
    this.heroTag = 'speed_dial_fab',
  });

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.value > 0) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void _select(SpeedDialAction action) {
    _controller.reverse();
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildActions(context),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: widget.heroTag,
          onPressed: _toggle,
          tooltip: '更多',
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Transform.rotate(
              angle: _controller.value * math.pi / 4,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (t <= 0) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < widget.actions.length; i++)
              _buildAction(context, scheme, widget.actions[i], t),
          ],
        );
      },
    );
  }

  Widget _buildAction(
    BuildContext context,
    ColorScheme scheme,
    SpeedDialAction action,
    double t,
  ) {
    final eased = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - eased) * 24),
          child: Material(
            color: scheme.surfaceContainer,
            elevation: 3,
            borderRadius: BorderRadius.circular(26),
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => _select(action),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(action.icon, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}