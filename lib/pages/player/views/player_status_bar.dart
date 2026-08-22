import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/player_controls_settings.dart';

/// 播放界面顶部信息行（工作.md 第 12 点 + 用户反馈重做）：
/// 在当前播放界面顶部单独拓展的一行区域，显示**时间与电量**。
///
/// - 显示内容由「播放器设置 → 顶部信息」控制：关闭 / 只显示时间 /
///   只显示电量 / 时间与电量（[TopStatusDisplay]）；
/// - **关闭时不渲染任何内容、不占高度**（Row 直接不参与布局）；
/// - **时间与电量居中显示**（用户反馈：上一版一边时间一边电量不对），
///   中间用分隔点隔开；字号 11（小于标题 16），轻量提示；
/// - **阴影/渐变由页面层统一提供**（用户反馈 v2：本行自带渐变与顶栏
///   渐变拼接时出现断层——最强的暗色带落在时间/电量行**下方**，割裂感
///   明显）：本行与顶栏不再各自画渐变，改由播放页把「信息行 + 顶栏」
///   整体包在一个连续渐变容器里（顶部最暗 → 向下淡出），视觉上是
///   同一个顶部渐变，阴影位置正确；
/// - 竖屏下高度压缩（padding 更小），避免把竖屏顶栏大幅往下顶
///   （用户反馈：竖屏顶得太多）。
///
/// 时间每 30 秒刷新；电量每 60 秒刷新（原生 BatteryManager）。
class PlayerStatusBar extends StatefulWidget {
  /// 是否竖屏（竖屏压缩高度）
  final bool portrait;

  const PlayerStatusBar({super.key, this.portrait = false});

  @override
  State<PlayerStatusBar> createState() => _PlayerStatusBarState();
}

class _PlayerStatusBarState extends State<PlayerStatusBar> {
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  /// 当前时间文本（HH:mm，每分钟刷新）
  String _timeText = '';

  /// 当前电量（0 – 100；null = 未知，不显示）
  int? _battery;

  Timer? _timeTimer;
  Timer? _batteryTimer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateTime(),
    );
    _refreshBattery();
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshBattery(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final text = '$hh:$mm';
    if (mounted && text != _timeText) setState(() => _timeText = text);
  }

  Future<void> _refreshBattery() async {
    final level = await DeviceServices.getBatteryLevel();
    if (mounted && level != _battery) setState(() => _battery = level);
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final display = _settings.topStatusDisplay;
        // 关闭：不渲染任何内容、不占高度
        if (display == TopStatusDisplay.off) {
          return const SizedBox.shrink();
        }
        final showTime =
            display != TopStatusDisplay.battery && _timeText.isNotEmpty;
        final showBattery =
            display != TopStatusDisplay.time && _battery != null;
        if (!showTime && !showBattery) return const SizedBox.shrink();

        // 竖屏高度更紧凑（用户反馈：竖屏顶栏被顶得太多）
        final vPad = widget.portrait ? 2.0 : 4.0;
        // 背景渐变已上移到页面层（PlayerStatusBar + 顶栏整体一个连续渐变，
        // 见文件头注释）：这里只渲染内容，避免两段渐变拼接产生断层。
        return Padding(
          padding: EdgeInsets.fromLTRB(
            kPlayerLeftInset,
            widget.portrait ? 0 : 2,
            kPlayerRightInset,
            vPad,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showTime)
                Text(
                  _timeText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: widget.portrait ? 10 : 11,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (showTime && showBattery) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 2,
                    height: widget.portrait ? 8 : 10,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
              if (showBattery)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _batteryIcon(_battery!),
                      size: widget.portrait ? 12 : 14,
                      color: _battery! <= 20
                          ? const Color(0xFFFFB74D)
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$_battery%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: widget.portrait ? 10 : 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  static IconData _batteryIcon(int level) {
    if (level <= 15) return Icons.battery_alert_rounded;
    if (level <= 30) return Icons.battery_2_bar_rounded;
    if (level <= 50) return Icons.battery_3_bar_rounded;
    if (level <= 70) return Icons.battery_4_bar_rounded;
    return Icons.battery_full_rounded;
  }
}

/// 顶部信息行右缘对齐（与顶栏「更多」按钮右缘一致）
const double kPlayerRightInset = 12;
