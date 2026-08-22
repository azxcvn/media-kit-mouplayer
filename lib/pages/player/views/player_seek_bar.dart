import 'package:flutter/material.dart';
import 'package:moumou/models/chapter_info.dart';
import 'package:moumou/pages/player/player_metrics.dart';

/// 全宽进度条（自定义绘制，替代 Material Slider）：
/// 拖动实时预览目标时间，松手/点击跳转。
///
/// 为什么不用 Slider（历史坑，勿改回）：
/// - Material Slider 的轨道默认内缩（thumb/overlay 半径，约 14px），
///   轨道起点无法与返回箭头/时间/下一集精确对齐到 [kPlayerLeftInset]；
/// - 拖动/点击判定受 Slider 内部 padding 与手势竞技场影响，体验不稳定。
///
/// 本实现直接绘制轨道与拇指，手势自管（点击轨道即跳转、拖动跟手），
/// 轨道起点精确落在 [kPlayerLeftInset]、右缘留 20 与底栏对齐。
///
/// 触摸反馈（工作.md 第 1 点）：拇指被**触摸或拖动**时，在外面套一个
/// 比拇指大一圈的同心圆（低透明度），让用户感知已命中进度条
/// （轻微放大 + 外圈扩散效果）。
class PlayerSeekBar extends StatefulWidget {
  final double valueMs;
  final double maxMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  /// 章节列表（秒）：非空时在轨道上绘制章节节点小圆点
  /// （工作.md 章节功能：未播放到=白色，播放过=主题色带透明度）
  final List<ChapterInfo> chapters;

  /// 可跳过片段（OP/ED/预告等）：非空时在轨道上方绘制类型色时间段
  final List<SkipSegment> skipSegments;

  const PlayerSeekBar({
    super.key,
    required this.valueMs,
    required this.maxMs,
    required this.onChanged,
    required this.onChangeEnd,
    this.chapters = const [],
    this.skipSegments = const [],
  });

  /// 进度条整体高度（含可点击热区）
  static const double barHeight = 40;

  /// 右缘间距（与底栏按钮行右缘对齐）
  static const double rightInset = 20;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  /// 是否正处于「触摸 / 拖动」状态：为 true 时拇指外圈放大显示
  bool _interacting = false;

  void _setInteracting(bool v) {
    if (_interacting == v) return;
    setState(() => _interacting = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueMs = widget.valueMs;
    final maxMs = widget.maxMs;
    return SizedBox(
      height: PlayerSeekBar.barHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackLeft = kPlayerLeftInset;
          final trackWidth = (constraints.maxWidth -
                  trackLeft -
                  PlayerSeekBar.rightInset)
              .clamp(0.0, double.infinity);
          final fraction =
              maxMs > 0 ? (valueMs / maxMs).clamp(0.0, 1.0) : 0.0;
          final thumbDx = trackLeft + trackWidth * fraction;
          final centerY = PlayerSeekBar.barHeight / 2;

          void handleAt(double dx) {
            if (trackWidth <= 0 || maxMs <= 0) return;
            final f = ((dx - trackLeft) / trackWidth).clamp(0.0, 1.0);
            widget.onChanged(f * maxMs);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点击轨道：预览（onChanged）→ 松手即跳转（onChangeEnd，用点击位置计算）
            onTapDown: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onTapUp: (d) {
              _setInteracting(false);
              if (trackWidth <= 0 || maxMs <= 0) return;
              final f = ((d.localPosition.dx - trackLeft) / trackWidth)
                  .clamp(0.0, 1.0);
              widget.onChangeEnd(f * maxMs);
            },
            onTapCancel: () => _setInteracting(false),
            // 拖动：实时预览，松手跳转（与原有 onChanged/onChangeEnd 契约一致）
            onHorizontalDragStart: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) {
              _setInteracting(true);
              handleAt(d.localPosition.dx);
            },
            onHorizontalDragEnd: (_) {
              _setInteracting(false);
              widget.onChangeEnd(valueMs);
            },
            onHorizontalDragCancel: () {
              _setInteracting(false);
              widget.onChangeEnd(valueMs);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 底轨（未播放部分）
                Positioned(
                  left: trackLeft,
                  right: PlayerSeekBar.rightInset,
                  top: centerY - 1.25,
                  height: 2.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(1.25),
                    ),
                  ),
                ),
                // 跳过片段色段（工作.md 章节功能第 4 点）：
                // 与轨道同高同位置，画在轨道内（覆盖底轨）；
                // 已播放段（主题色）在其上覆盖，未播放区域显示类型色；
                // 色相用类型专属色，透明度压低避免与主题色冲突。
                ..._buildSkipSegments(trackLeft, trackWidth, centerY),
                // 已播放部分（主题色）
                Positioned(
                  left: trackLeft,
                  top: centerY - 1.25,
                  width: (thumbDx - trackLeft).clamp(0.0, trackWidth),
                  height: 2.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(1.25),
                    ),
                  ),
                ),
                // 章节节点小圆点（工作.md 章节功能第 1 点）：
                // 未播放到 = 白色，播放过 = 主题色带透明度（色相一致）；
                // 黑描边保证在亮画面视频上也清晰。
                ..._buildChapterDots(scheme, trackLeft, trackWidth, centerY),
                // 触摸/拖动反馈外圈：比拇指大一圈、低透明度，放大 + 淡入
                // （工作.md 第 1 点：被触摸时在小圆点外面套一个更大的圆形）
                Positioned(
                  left: thumbDx - 16,
                  top: centerY - 16,
                  child: IgnorePointer(
                    child: AnimatedScale(
                      scale: _interacting ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _interacting ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 拇指
                Positioned(
                  left: thumbDx - 6,
                  top: centerY - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 跳过片段色段：与轨道同高（2.5）画在轨道内（无端点标记，避免
  /// 遮盖章节圆点；色段本身的类型色已足够标识时间段）。
  List<Widget> _buildSkipSegments(
    double trackLeft,
    double trackWidth,
    double centerY,
  ) {
    if (widget.skipSegments.isEmpty || widget.maxMs <= 1.0) return const [];
    final durationSeconds = widget.maxMs / 1000.0;
    // 色带与轨道同高同位置：覆盖底轨，已播放段在上层再覆盖
    final bandTop = centerY - 1.25;
    return [
      for (final seg in widget.skipSegments)
        if (seg.startSeconds < durationSeconds)
          Positioned(
            left: trackLeft + trackWidth * (seg.startSeconds / durationSeconds),
            width: (trackWidth *
                    ((seg.endSeconds - seg.startSeconds) / durationSeconds))
                .clamp(0.0, trackWidth),
            top: bandTop,
            height: 2.5,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: seg.type.color.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(1.25),
                ),
              ),
            ),
          ),
    ];
  }

  /// 章节节点小圆点（直径 6，圆心在轨道中线）：
  /// - 未播放到（章节起点 > 当前播放位置）：白色 0.85；
  /// - 播放过：主题色 0.75（与进度条色相一致，透明度区分已播/未播）。
  List<Widget> _buildChapterDots(
    ColorScheme scheme,
    double trackLeft,
    double trackWidth,
    double centerY,
  ) {
    if (widget.chapters.isEmpty || widget.maxMs <= 1.0) return const [];
    final durationSeconds = widget.maxMs / 1000.0;
    final playedSeconds = widget.valueMs / 1000.0;
    return [
      for (final chapter in widget.chapters)
        if (chapter.startSeconds.isFinite &&
            chapter.startSeconds >= 0 &&
            chapter.startSeconds < durationSeconds)
          Positioned(
            left: trackLeft +
                trackWidth * (chapter.startSeconds / durationSeconds) -
                3,
            top: centerY - 3,
            child: IgnorePointer(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: playedSeconds >= chapter.startSeconds
                      ? scheme.primary.withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
    ];
  }
}
