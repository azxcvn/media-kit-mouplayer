import 'dart:async';

import 'package:flutter/material.dart';

/// 恢复上次播放进度指示器（横屏顶部弹出，独立于控制层显隐）。
///
/// - 文案：「已恢复上次播放进度｜重头开始｜关闭」；
/// - 「重头开始」：可点击，由页面执行 seek(0) 并继续播放，随后关闭指示器；
/// - 「关闭」：可点击（红色文本），仅关闭指示器；
/// - 5 秒无操作自动隐藏；
/// - 进出场动画与音量/亮度指示器（kazumi 风格）一致：从屏幕边缘滑入 +
///   淡入 + 轻微缩放（本组件从顶部滑入），退场反向。
class PlayerResumeIndicator extends StatefulWidget {
  /// 「重头开始」点击：页面执行 seek(0) + 继续播放
  final VoidCallback onRestart;

  /// 指示器关闭（「关闭」点击 / 5 秒自动隐藏 / 「重头开始」后都会触发）
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
  static const _autoHideDelay = Duration(seconds: 5);

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
    // 5 秒无操作自动隐藏
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 14, right: 8),
                    child: Text(
                      '已恢复上次播放进度',
                      style: TextStyle(color: Colors.white, fontSize: 14),
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
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '重头开始',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _dismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('关闭', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
