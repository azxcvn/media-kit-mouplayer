import 'dart:async';

import 'package:flutter/material.dart';

/// 恢复上次播放进度指示器（顶部弹出，独立于控制层显隐）。
///
/// - 文案：「已恢复上次播放进度｜重头开始｜关闭」；
/// - 「重头开始」：可点击，由页面执行 seek(0) 并继续播放，随后关闭指示器；
/// - 「关闭」：可点击（红色文本），仅关闭指示器；
/// - 2.5 秒无操作自动隐藏；
/// - **胶囊式包裹**（工作.md 第 2 点）：整体为药丸形（完全圆角），
///   参考倍速列表/倍速指示器的胶囊样式，深色半透明底 + 白字；
/// - 进出场动画与音量/亮度指示器（kazumi 风格）一致：从顶部滑入 +
///   淡入 + 轻微缩放，退场反向。
class PlayerResumeIndicator extends StatefulWidget {
  /// 「重头开始」点击：页面执行 seek(0) + 继续播放
  final VoidCallback onRestart;

  /// 指示器关闭（「关闭」点击 / 自动隐藏 / 「重头开始」后都会触发）
  final VoidCallback onClose;

  const PlayerResumeIndicator({
    super.key,
    required this.onRestart,
    required this.onClose,
  });

  @override
  State<PlayerResumeIndicator> createState() => _PlayerResumeIndicatorState();
}

class _PlayerResumeIndicatorState extends State<PlayerResumeIndicator>
    with SingleTickerProviderStateMixin {
  static const _autoHideDelay = Duration(milliseconds: 2500);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  ));
  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  Timer? _hideTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // 进场：顶部滑入 + 淡入 + 缩放（post-frame 启动，避免首帧前倒播动画）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
    _hideTimer = Timer(_autoHideDelay, _dismiss);
  }

  /// 退场：滑出 + 淡出，动画结束后通知页面移除
  void _dismiss() {
    if (_closing) return;
    _closing = true;
    _hideTimer?.cancel();
    _controller.reverse().whenComplete(() {
      if (mounted) widget.onClose();
    });
  }

  void _handleRestart() {
    widget.onRestart();
    _dismiss();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: SlideTransition(
          position: _slide,
          child: IgnorePointer(
            ignoring: _closing,
            // 胶囊式包裹：完全圆角（药丸形），参考倍速胶囊样式
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                // 轻描边让胶囊更立体（kazumi 风格）
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      '已恢复上次播放进度',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _handleRestart,
                    style: TextButton.styleFrom(
                      // 主题蓝（与倍速指示器高亮同色）
                      foregroundColor: const Color(0xFF4FC3F7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '重头开始',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _dismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('关闭', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
