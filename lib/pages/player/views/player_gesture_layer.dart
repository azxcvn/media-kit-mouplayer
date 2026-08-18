import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 单指手势方向
enum _LayerGestureKind { horizontal, verticalLeft, verticalRight, zoom }

/// 播放页手势层：统一处理全部触摸手势（思路对齐 PiliPlus 的
/// `MouseInteractiveViewer` + 裸手势识别器方案，避免 GestureDetector
/// 多手势竞争导致的判定漂移）：
///
/// - **单击**：切换控制层显隐（锁定态由页面自行处理解锁按钮）；
/// - **双击**：按设置执行暂停 / 快退快进；
/// - **长按（500ms 无移动）**：进入长按倍速，长按期间手指横向移动
///   通过 [onLongPressUpdate] 逐帧回调（动态调速），松手恢复原速；
/// - **单指滑动**：位移超过阈值后延迟 80ms 再确认方向（垂直/水平），
///   给第二根手指留出加入时间，双指捏合不再误触发滑动；
///   垂直按起始横坐标分左右（左=亮度、右=音量）；
///   顶部/底部 8% 为垂直手势死区、右侧 8% 为水平手势死区
///   （避免与全面屏系统手势冲突，参考 kt 项目）；
/// - **双指**：缩放 + 平移画面（[onZoomStart]/[onZoomUpdate]/[onZoomEnd]），
///   若滑动中途加入第二指，先回调 [onSwipeCancel] 供页面撤销 seek。
///
/// 锁定态（[locked]）只放行单击，其余手势一律拦截。
class PlayerGestureLayer extends StatefulWidget {
  /// 手势层覆盖的内容（视频画面等，透明叠加在上层即可）
  final Widget child;

  /// 控制层是否锁定（锁定后仅单击放行）
  final bool locked;

  /// 单击（任意态都会回调，页面自行处理锁定分支）
  final VoidCallback onTap;

  /// 双击（仅未锁定）
  final ValueChanged<Offset> onDoubleTap;

  /// 长按开始（未锁定，参数为按下位置，页面据此记录调速起点）
  final ValueChanged<Offset> onLongPressStart;

  /// 长按期间手指移动（参数为当前位置，页面计算横向位移调速）
  final ValueChanged<Offset> onLongPressUpdate;

  /// 长按结束 / 取消
  final VoidCallback onLongPressEnd;

  /// 单指方向滑动开始（页面记录 seek 起点 / 重置累加器）
  final VoidCallback onSwipeStart;

  /// 单指方向滑动被双指手势打断（用户意图改为缩放）时回调，
  /// 页面据此撤销已发生的 seek，避免「缩放时误触发左右滑动」
  final VoidCallback onSwipeCancel;

  /// 垂直滑动：[dyDelta] 为本次更新的纵向位移（向上为负），
  /// [isLeftHalf] 为起始点是否在左半屏。
  final void Function(double dyDelta, bool isLeftHalf) onVerticalSwipe;

  /// 水平滑动：[totalDx] 为自手势开始累计的横向位移（右滑为正）。
  final ValueChanged<double> onHorizontalSwipe;

  /// 单指滑动结束（页面清除 seek 预览等）
  final VoidCallback onSwipeEnd;

  /// 双指手势开始（页面记录缩放起点）
  final VoidCallback onZoomStart;

  /// 双指缩放/平移（原始 ScaleUpdateDetails，pointerCount >= 2）
  final ValueChanged<ScaleUpdateDetails> onZoomUpdate;

  /// 双指手势结束
  final VoidCallback onZoomEnd;

  const PlayerGestureLayer({
    super.key,
    required this.child,
    required this.locked,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPressStart,
    required this.onLongPressUpdate,
    required this.onLongPressEnd,
    required this.onSwipeStart,
    required this.onVerticalSwipe,
    required this.onHorizontalSwipe,
    required this.onSwipeEnd,
    required this.onSwipeCancel,
    required this.onZoomStart,
    required this.onZoomUpdate,
    required this.onZoomEnd,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  static const double _kDragSlop = 20;
  static const double _kVerticalDeadZoneRatio = 0.08;
  static const double _kHorizontalDeadZoneRatio = 0.08;

  /// 方向分类延迟：单指位移超阈值后等待一小段时间再确认方向，
  /// 给第二根手指留出加入时间（双指捏合前单指微动不再误判为滑动）
  static const Duration _kClassifyDelay = Duration(milliseconds: 80);

  /// 首个按下位置（用于方向判定与死区检查）
  Offset? _downPosition;
  final Set<int> _activePointers = {};
  _LayerGestureKind? _kind;
  bool _longPressing = false;
  double _gestureDx = 0;

  /// 本次手势是否出现过双指（出现后单指不再分类方向，防捏合误触滑动）
  bool _seenMultiTouch = false;

  /// 最近一次单指焦点（延迟分类时使用）
  Offset? _lastFocalPoint;
  Timer? _classifyTimer;
  bool _gestureActive = false;

  double _width = 0;
  double _height = 0;

  void _endLongPress() {
    if (!_longPressing) return;
    _longPressing = false;
    widget.onLongPressEnd();
  }

  void _cancelClassifyTimer() {
    _classifyTimer?.cancel();
    _classifyTimer = null;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureDx = 0;
    _gestureActive = true;
    _seenMultiTouch = d.pointerCount >= 2;
    _lastFocalPoint = d.localFocalPoint;
    _cancelClassifyTimer();
    if (d.pointerCount >= 2) {
      _kind = _LayerGestureKind.zoom;
      widget.onZoomStart();
    } else {
      _kind = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (widget.locked) return;

    // 双指：缩放/平移（单指中途加入第二指时也切换到缩放）
    if (d.pointerCount >= 2) {
      _seenMultiTouch = true;
      _cancelClassifyTimer();
      if (_kind != _LayerGestureKind.zoom) {
        // 已开始的方向滑动被双指打断：先撤销，再进入缩放
        if (_kind != null) widget.onSwipeCancel();
        _kind = _LayerGestureKind.zoom;
        widget.onZoomStart();
      }
      widget.onZoomUpdate(d);
      return;
    }

    // 双指变单指：本次手势作废，避免缩放中误触发方向滑动
    if (_kind == _LayerGestureKind.zoom) return;
    _lastFocalPoint = d.localFocalPoint;

    // 未分类：超过阈值后延迟确认方向（见 _kClassifyDelay 注释）
    if (_kind == null) {
      final down = _downPosition;
      if (down == null) return;
      final dx = (d.localFocalPoint.dx - down.dx).abs();
      final dy = (d.localFocalPoint.dy - down.dy).abs();
      final crossed =
          (dy > dx && dy > _kDragSlop) || (dx > dy && dx > _kDragSlop);
      if (crossed && !_seenMultiTouch && _classifyTimer == null) {
        _classifyTimer = Timer(_kClassifyDelay, _confirmDirection);
      }
      return;
    }

    switch (_kind) {
      case _LayerGestureKind.horizontal:
        _gestureDx += d.focalPointDelta.dx;
        widget.onHorizontalSwipe(_gestureDx);
      case _LayerGestureKind.verticalLeft:
        widget.onVerticalSwipe(d.focalPointDelta.dy, true);
      case _LayerGestureKind.verticalRight:
        widget.onVerticalSwipe(d.focalPointDelta.dy, false);
      case _LayerGestureKind.zoom:
      case null:
        break;
    }
  }

  /// 延迟确认单指滑动方向（含死区检查）。
  /// 水平滑动把延迟期间的位移并入起始位移，保证 seek 目标不丢位移。
  void _confirmDirection() {
    _classifyTimer = null;
    if (!_gestureActive || _seenMultiTouch || _kind != null) return;
    final down = _downPosition;
    final current = _lastFocalPoint;
    if (down == null || current == null) return;
    final dx = (current.dx - down.dx).abs();
    final dy = (current.dy - down.dy).abs();
    if (dy > dx && dy > _kDragSlop) {
      // 顶部/底部死区：全面屏手势（下拉通知栏/上滑手势）不处理
      if (down.dy < _height * _kVerticalDeadZoneRatio ||
          down.dy > _height * (1 - _kVerticalDeadZoneRatio)) {
        return;
      }
      _kind = down.dx < _width / 2
          ? _LayerGestureKind.verticalLeft
          : _LayerGestureKind.verticalRight;
      widget.onSwipeStart();
    } else if (dx > dy && dx > _kDragSlop) {
      // 右侧死区：系统返回手势，不处理
      if (down.dx > _width * (1 - _kHorizontalDeadZoneRatio)) {
        return;
      }
      _kind = _LayerGestureKind.horizontal;
      // 延迟期间的水平位移并入起始位移，seek 从按下位置算起
      _gestureDx = current.dx - down.dx;
      widget.onSwipeStart();
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _gestureActive = false;
    _cancelClassifyTimer();
    final kind = _kind;
    _kind = null;
    if (kind == _LayerGestureKind.zoom) {
      widget.onZoomEnd();
    } else if (kind != null) {
      widget.onSwipeEnd();
    }
  }

  @override
  void dispose() {
    _cancelClassifyTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            _activePointers.add(e.pointer);
            _downPosition ??= e.localPosition;
          },
          onPointerMove: (e) {
            // 长按已生效时逐帧回调（手势竞技场中长按胜出，滑动识别器
            // 不再收到事件，靠这里的裸指针事件实现「长按 + 左右滑动」调速）
            if (_longPressing && !widget.locked) {
              widget.onLongPressUpdate(e.localPosition);
            }
          },
          onPointerUp: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.isEmpty) _downPosition = null;
          },
          onPointerCancel: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.isEmpty) {
              _downPosition = null;
              // 指针取消（系统抢占）也可能中断识别器：清理待分类状态
              _cancelClassifyTimer();
              _gestureActive = false;
            }
            // 指针取消也结束长按
            if (_longPressing && !widget.locked) _endLongPress();
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  TapGestureRecognizer>(
                () => TapGestureRecognizer(),
                (r) => r
                  ..onTapUp = (_) => widget.onTap(),
              ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(),
                (r) => r
                  ..onDoubleTapDown = (d) {
                    if (widget.locked) return;
                    widget.onDoubleTap(d.localPosition);
                  },
              ),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 500),
                ),
                (r) => r
                  ..onLongPressStart = (d) {
                    if (widget.locked) return;
                    _longPressing = true;
                    widget.onLongPressStart(d.localPosition);
                  }
                  ..onLongPressEnd = (_) {
                    _endLongPress();
                  }
                  ..onLongPressCancel = _endLongPress,
              ),
              ScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      ScaleGestureRecognizer>(
                () => ScaleGestureRecognizer(),
                (r) => r
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd,
              ),
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
