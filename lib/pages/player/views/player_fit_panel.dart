import 'package:flutter/material.dart';
import 'package:moumou/models/player_action.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/player_option_chip.dart';

/// 画面比例设置面板内容（通过 [showPlayerPanel] 弹出，与倍速/超分面板同一套外壳与胶囊）。
///
/// 布局为固定三行、行内四等分等宽：
/// - 第一行四个：拉伸 / 裁剪 / 等宽 / 等高；
/// - 第二行四个：原始 / 限制 / 4:3 / 16:9；
/// - 第三行「自动」独占一行，宽度与上面两行一致（四等分宽）。
/// 点击立即生效并持久化（默认「自动」）。
class PlayerFitPanel extends StatefulWidget {
  const PlayerFitPanel({super.key});

  @override
  State<PlayerFitPanel> createState() => _PlayerFitPanelState();
}

class _PlayerFitPanelState extends State<PlayerFitPanel> {
  final PlayerControlsSettings _settings = PlayerControlsSettings.instance;

  /// 前两行：每行四个（四等分等宽）
  static const List<List<PlayerVideoFit>> _fitRows = [
    [
      PlayerVideoFit.fill,
      PlayerVideoFit.cover,
      PlayerVideoFit.fitWidth,
      PlayerVideoFit.fitHeight,
    ],
    [
      PlayerVideoFit.none,
      PlayerVideoFit.scaleDown,
      PlayerVideoFit.ratio4x3,
      PlayerVideoFit.ratio16x9,
    ],
  ];

  @override
  void initState() {
    super.initState();
    // 面板是独立弹窗路由，播放页 setState 不会重建面板；
    // 监听设置变化刷新选中态
    _settings.addListener(_handleChanged);
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_handleChanged);
    super.dispose();
  }

  Widget _buildFitRow(List<PlayerVideoFit> row) {
    return Row(
      children: [
        for (var i = 0; i < row.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _buildFitChip(row[i])),
        ],
      ],
    );
  }

  Widget _buildFitChip(PlayerVideoFit fit) {
    return PlayerOptionChip(
      label: fit.label,
      selected: _settings.videoFit == fit,
      onTap: () => _settings.setVideoFit(fit),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 面板标题已是「画面比例」，内容直接铺胶囊，顶部留白最小
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        children: [
          for (final row in _fitRows) ...[
            _buildFitRow(row),
            const SizedBox(height: 8),
          ],
          // 第三行：「自动」独占一行，四等分宽（与上面两行一致）
          _buildFitRow(const [PlayerVideoFit.contain]),
        ],
      ),
    );
  }
}
