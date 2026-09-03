import 'package:flutter/material.dart';
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/widgets/player_option_chip.dart';

/// 清晰度面板：列出当前账号可选的画质档（`accept_quality`），当前档高亮，
/// 点击切换画质（切换由父级重新解析 playurl 并重开播放保持进度）。
///
/// 点击后乐观更新高亮，切换失败回退高亮（父级 [onSelect] 返回是否成功）。
class PlayerQualityPanel extends StatefulWidget {
  const PlayerQualityPanel({
    super.key,
    required this.qualities,
    required this.currentQn,
    required this.onSelect,
  });

  final List<BiliQualityOption> qualities;
  final int currentQn;
  final Future<bool> Function(int qn) onSelect;

  @override
  State<PlayerQualityPanel> createState() => _PlayerQualityPanelState();
}

class _PlayerQualityPanelState extends State<PlayerQualityPanel> {
  late int _currentQn = widget.currentQn;
  bool _switching = false;

  Future<void> _select(int qn) async {
    if (_switching || qn == _currentQn) return;
    setState(() {
      _switching = true;
      _currentQn = qn;
    });
    final ok = await widget.onSelect(qn);
    if (!mounted) return;
    setState(() {
      if (!ok) _currentQn = widget.currentQn; // 失败回退高亮
      _switching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.qualities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '暂无可用画质',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.qualities.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var j = 0; j < 2 && i + j < widget.qualities.length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: PlayerOptionChip(
                      label: widget.qualities[i + j].description,
                      selected: widget.qualities[i + j].qn == _currentQn,
                      onTap: () => _select(widget.qualities[i + j].qn),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '切换画质会重开播放并保持进度',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
