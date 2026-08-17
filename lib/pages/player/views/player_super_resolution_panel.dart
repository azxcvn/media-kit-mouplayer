import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/super_resolution_mode.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/widgets/player_option_chip.dart';

/// 超分辨率设置面板内容（通过 [showPlayerPanel] 弹出，与倍速面板同一套外壳与胶囊）。
///
/// 布局（自上而下）：
/// - 「模式」：三行固定布局，行内三等分等宽 —
///   第一行 A/B/C、第二行 A+/B+/C+、第三行「关闭」独占一行（宽度与上面两行一致）；
/// - 当前模式的说明文字；
/// - 「超分质量」：一行三个胶囊（流畅 / 均衡 / 高清，默认均衡）；
/// - 「记忆超分模式」开关：默认关闭，开启后自动应用上次的模式与质量到所有视频。
///
/// 直接驱动 [SuperResolutionService] 单例（模式/质量/记忆均持久化）。
class PlayerSuperResolutionPanel extends StatefulWidget {
  /// 播放器实例（切换模式/质量时立即应用；null 时仅改设置）
  final Player? player;

  const PlayerSuperResolutionPanel({super.key, this.player});

  @override
  State<PlayerSuperResolutionPanel> createState() =>
      _PlayerSuperResolutionPanelState();
}

class _PlayerSuperResolutionPanelState
    extends State<PlayerSuperResolutionPanel> {
  /// 前两行：每行三个模式（三等分等宽）
  static const List<List<SuperResolutionMode>> _modeRows = [
    [SuperResolutionMode.a, SuperResolutionMode.b, SuperResolutionMode.c],
    [
      SuperResolutionMode.aPlus,
      SuperResolutionMode.bPlus,
      SuperResolutionMode.cPlus,
    ],
  ];

  final SuperResolutionService _service = SuperResolutionService.instance;

  @override
  void initState() {
    super.initState();
    // 面板是独立弹窗路由，播放页 setState 不会重建面板；
    // 监听服务变化刷新选中态/开关/说明
    _service.addListener(_handleServiceChanged);
  }

  void _handleServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  Widget _buildModeRow(List<SuperResolutionMode> row) {
    return Row(
      children: [
        for (var i = 0; i < row.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _buildModeChip(row[i])),
        ],
      ],
    );
  }

  Widget _buildModeChip(SuperResolutionMode mode) {
    return PlayerOptionChip(
      label: mode.label,
      selected: _service.mode == mode,
      onTap: () => _service.setMode(mode, player: widget.player),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildQualityRow() {
    return Row(
      children: [
        for (var i = 0; i < SuperResolutionQuality.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _buildQualityChip(SuperResolutionQuality.values[i])),
        ],
      ],
    );
  }

  Widget _buildQualityChip(SuperResolutionQuality quality) {
    return PlayerOptionChip(
      label: quality.label,
      selected: _service.quality == quality,
      onTap: () => _service.setQuality(quality, player: widget.player),
      textAlign: TextAlign.center,
    );
  }

  /// 「当前生效」区已移除（属调试信息，超分生效已验证）。

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 模式（第一眼）──
          const _SectionLabel('模式'),
          const SizedBox(height: 8),
          for (final row in _modeRows) ...[
            _buildModeRow(row),
            const SizedBox(height: 8),
          ],
          // ── 第三行：关闭独占一行，等宽（与上面两行每个胶囊同宽）──
          _buildModeRow(const [SuperResolutionMode.off]),
          const SizedBox(height: 16),
          // ── 当前模式说明 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _service.mode.description,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── 超分质量（一行三个胶囊）──
          const _SectionLabel('超分质量'),
          const SizedBox(height: 8),
          _buildQualityRow(),
          const SizedBox(height: 16),
          // ── 记忆超分模式开关 ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: Icon(Icons.history, color: Colors.white70, size: 22),
              title: const Text(
                '记忆超分模式',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: const Text(
                '开启后自动应用上次的超分模式与质量',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: Switch(
                value: _service.remember,
                activeThumbColor: scheme.primary,
                // 带 player：关掉记忆立即清除当前视频着色器，开启立即恢复上次模式
                onChanged: (v) => _service.setRemember(v, player: widget.player),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 小节标题（模式 / 超分质量 / 当前生效）
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
