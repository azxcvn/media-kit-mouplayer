import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moumou/pages/player/player_metrics.dart';
import 'package:moumou/services/bilibili/bili_stream_proxy.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/network/network_streaming_proxy.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/utils/formatters.dart';

/// 播放界面顶部信息行（工作.md 阶段1 第 1 点重做）：
///
/// 顶部区域可显示四类信息，由「播放器设置 → 顶部信息」多选控制
/// （时间 / 电量 / 网速详情 / 数据类型，默认全选）：
/// - **时间 / 电量**：居中显示（与旧版一致），中间用分隔点隔开；
/// - **网速详情**：胶囊式包裹，自动切换 KB/MB、精确到小数点后两位；
///   **仅在线播放时显示**（本地播放即使勾选也不显示，见 [isOnlinePlayback]）；
/// - **数据类型**：WiFi / 移动数据 / 以太网图标（无网络时不显示）。
///
/// **布局规则（工作.md 阶段1 第 1 点）**：网速详情与数据类型的显示位置
/// 取决于是否勾选了时间或电量——
/// - 勾选了时间 **或** 电量 → 时间/电量居中，网速+数据类型靠**最右**（网速在数据类型左侧）；
/// - 时间、电量都未勾选 → 网速+数据类型整体**居中**显示（与时间/电量居中逻辑一致）。
///
/// 关闭时（四项全未勾选）不渲染任何内容、不占高度。
/// 阴影/渐变由页面层统一提供（信息行 + 顶栏整体一个连续渐变，避免断层）。
///
/// 刷新频率：时间 30s、电量 60s、网络类型 5s、网速 1s（滑动窗口真实速率）。
class PlayerStatusBar extends StatefulWidget {
  /// 是否竖屏（竖屏压缩高度）
  final bool portrait;

  /// 是否为在线播放（网速详情仅在线播放时显示；本地播放一律隐藏）。
  final bool isOnlinePlayback;

  /// 在线播放时的回环代理流 URL。内部据此轮询已传输字节数计算网速；
  /// 本地播放传 null 即可。
  final String? streamUrl;

  const PlayerStatusBar({
    super.key,
    this.portrait = false,
    this.isOnlinePlayback = false,
    this.streamUrl,
  });

  @override
  State<PlayerStatusBar> createState() => _PlayerStatusBarState();
}

class _PlayerStatusBarState extends State<PlayerStatusBar> {
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  /// 当前时间文本（HH:mm，每分钟刷新）
  String _timeText = '';

  /// 当前电量（0 – 100；null = 未知，不显示）
  int? _battery;

  /// 当前网络类型（'wifi' / 'cellular' / 'ethernet' / 'none'）
  String _netType = 'none';

  /// 网速（字节/秒）：每秒读取代理层「最近 1 秒滑动窗口」的真实下行速率。
  double _netSpeedBytesPerSec = 0;

  Timer? _timeTimer;
  Timer? _batteryTimer;
  Timer? _netTypeTimer;
  Timer? _netSpeedTimer;

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
    _refreshNetType();
    _netTypeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshNetType(),
    );
    _tickNetSpeed();
    _netSpeedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickNetSpeed(),
    );
  }

  @override
  void didUpdateWidget(covariant PlayerStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切集 / 换源：流 URL 或在线状态变了，重置网速显示，避免残留上一集的速度。
    if (oldWidget.streamUrl != widget.streamUrl ||
        oldWidget.isOnlinePlayback != widget.isOnlinePlayback) {
      _netSpeedBytesPerSec = 0;
    }
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

  Future<void> _refreshNetType() async {
    final type = await DeviceServices.getNetworkType();
    if (mounted && type != _netType) setState(() => _netType = type);
  }

  /// 每秒采样一次网速：直接读取代理层「最近 1 秒滑动窗口」的真实下行速率。
  /// 不做差分、不做平滑，稳定且贴近实际下载速度；播放期间胶囊常驻（见 build 中显示条件）。
  void _tickNetSpeed() {
    if (!widget.isOnlinePlayback || widget.streamUrl == null) {
      if (_netSpeedBytesPerSec != 0) setState(() => _netSpeedBytesPerSec = 0);
      return;
    }
    // 网速来源按代理类型分流（工作.md 第 6 点——之前只读网络存储代理，B 站恒为 0 KB/s）：
    // - 网络存储播放：streamUrl 就是本地代理 URL，按 URL 匹配查 NetworkStreamingProxy；
    // - B 站在线播放：streamUrl 是 CDN 原始 URL（本地代理 URL 只在播放器内部使用），
    //   按匹配查不到，改读 BiliStreamProxy 全部流（video+audio）的聚合速率。
    final speed = NetworkStreamingProxy.instance
            .recentSpeedBytesPerSec(widget.streamUrl!) ??
        BiliStreamProxy.instance.recentTotalSpeedBytesPerSec();
    if (speed == null) return;
    if ((speed - _netSpeedBytesPerSec).abs() > 1.0) {
      setState(() => _netSpeedBytesPerSec = speed);
    }
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _batteryTimer?.cancel();
    _netTypeTimer?.cancel();
    _netSpeedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final s = _settings;
        final showTime = s.showTopTime && _timeText.isNotEmpty;
        final showBattery = s.showTopBattery && _battery != null;
        // 网速详情：仅在线播放时显示（本地播放一律隐藏）。
        // 播放期间胶囊常驻，速度无数据时平滑衰减而非消失，符合「一直显示」的直觉。
        final showNetSpeed = s.showTopNetSpeed && widget.isOnlinePlayback;
        // 数据类型：无网络（'none'）时不显示图标
        final showNetType = s.showTopNetType && _netType != 'none';

        final hasCenter = showTime || showBattery;
        final hasNet = showNetSpeed || showNetType;
        // 四项都不可见：不渲染、不占高度
        if (!hasCenter && !hasNet) return const SizedBox.shrink();

        // 竖屏高度更紧凑
        final vPad = widget.portrait ? 2.0 : 4.0;
        final padding = EdgeInsets.fromLTRB(
          kPlayerLeftInset,
          widget.portrait ? 0 : 2,
          kPlayerRightInset,
          vPad,
        );

        final netGroup = _buildNetGroup(showNetSpeed, showNetType);
        // 网速/数据类型图标整体靠右，但用户要求再往里挪一点（横竖屏都要），
        // 避免贴边/与系统状态图标挤在一起：在原有对齐基础上再内缩 8dp。
        final netRightPad = widget.portrait ? 17.0 : 21.0;

        if (hasCenter) {
          // 勾选了时间/电量：时间电量居中，网速+数据类型靠最右。
          // 外层 Column 是松宽度约束，Stack 会收缩到居中组那点宽度，
          // 导致 right:0 相对的是收缩后的 Stack 而非屏幕右缘；故先撑满整行。
          return Padding(
            padding: padding,
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _buildCenterGroup(showTime, showBattery),
                  if (hasNet)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(right: netRightPad),
                          child: netGroup,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        // 只勾了网速/数据类型：整体居中显示
        return Padding(
          padding: padding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [netGroup],
          ),
        );
      },
    );
  }

  /// 居中组：时间 + 分隔点 + 电量
  Widget _buildCenterGroup(bool showTime, bool showBattery) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
        if (showTime && showBattery)
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
    );
  }

  /// 网络组：网速详情胶囊（左）+ 数据类型图标（右）
  Widget _buildNetGroup(bool showNetSpeed, bool showNetType) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showNetSpeed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              formatNetworkSpeed(_netSpeedBytesPerSec),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: widget.portrait ? 9 : 10,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (showNetType) const SizedBox(width: 6),
        ],
        if (showNetType) _buildNetTypeIcon(),
      ],
    );
  }

  /// 数据类型图标：WiFi / 移动数据 / 以太网
  Widget _buildNetTypeIcon() {
    final size = widget.portrait ? 12.0 : 14.0;
    final color = Colors.white.withValues(alpha: 0.85);
    return switch (_netType) {
      'wifi' => Icon(Icons.wifi_rounded, size: size, color: color),
      'cellular' =>
        Icon(Icons.signal_cellular_alt_rounded, size: size, color: color),
      'ethernet' => Icon(Icons.settings_ethernet_rounded, size: size, color: color),
      _ => const SizedBox.shrink(),
    };
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
