import 'package:flutter/material.dart';
import 'package:moumou/models/player_loop.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/player_option_chip.dart';

/// 循环播放模式面板内容（竖屏底部面板 / 横屏右侧面板共用）。
///
/// 三个选项胶囊：关闭 / 列表循环 / 单集循环，绑定
/// [PlayerControlsSettings.instance.loopMode]（ChangeNotifier，
/// ListenableBuilder 实时刷新选中态）。
///
/// 布局与 [PlayerFitPanel] 一致：一行三等分等宽胶囊。
class PlayerLoopPanel extends StatelessWidget {
  const PlayerLoopPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerControlsSettings.instance,
      builder: (context, _) {
        final settings = PlayerControlsSettings.instance;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Row(
            children: [
              for (var i = 0; i < LoopMode.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: PlayerOptionChip(
                    label: LoopMode.values[i].label,
                    selected: settings.loopMode == LoopMode.values[i],
                    onTap: () => settings.setLoopMode(LoopMode.values[i]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
