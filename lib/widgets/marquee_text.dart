import 'package:flutter/material.dart';

/// 跑马灯文本：文本超出一行时，自动从左到右无缝循环滚动显示完整内容。
///
/// 实现方式：溢出时渲染两份文本（中间留固定间隔），滚动总距离 = 一份文本宽
/// + 间隔。动画循环到终点跳回起点时，第二份文本正好接在第一份末尾，
/// 视觉上形成头尾相接的无缝循环。
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  /// 两份文本之间的间隔（无缝衔接的最小间隙）
  final double gap;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.gap = 48,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _animation;
  double _scrollRange = 0; // 一份文本宽 + 间隔（一次完整循环的滚动距离）
  bool _overflow = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..addListener(() {
            if (_scrollController.hasClients && _overflow) {
              _scrollController.jumpTo(_scrollRange * _animation.value);
            }
          });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      // 文本变化：回到起点，由 build 中的溢出判断决定是否重新循环
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = painter.width;
        _overflow = textWidth > constraints.maxWidth;
        _scrollRange = _overflow ? textWidth + widget.gap : 0;

        if (_overflow && !_animation.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _overflow && !_animation.isAnimating) {
              _animation.repeat();
            }
          });
        } else if (!_overflow && _animation.isAnimating) {
          _animation.stop();
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        }

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.text, style: widget.style, maxLines: 1),
              // 溢出时追加间隔与第二份文本，实现无缝衔接
              if (_overflow) ...[
                SizedBox(width: widget.gap),
                Text(widget.text, style: widget.style, maxLines: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}
