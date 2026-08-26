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
              // 显示顺序：关闭 → 单集循环 → 列表循环（enum 顺序不变，
              // 持久化按 index，避免改 enum 顺序导致已存值错位）
              for (final mode in const [
                LoopMode.off,
                LoopMode.repeatOne,
                LoopMode.loopAll,
              ]) ...[
                if (mode != LoopMode.off) const SizedBox(width: 8),
                Expanded(
                  child: PlayerOptionChip(
                    label: mode.label,
                    selected: settings.loopMode == mode,
                    onTap: () => settings.setLoopMode(mode),
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
