import 'package:flutter/material.dart';
import 'package:moumou/pages/settings/about_page.dart';
import 'package:moumou/pages/settings/appearance_page.dart';
import 'package:moumou/pages/settings/danmaku_server_page.dart';
import 'package:moumou/pages/settings/media_scan_settings_page.dart';
import 'package:moumou/pages/settings/player_settings_page.dart';
import 'package:moumou/theme/theme_controller.dart';
import 'package:moumou/widgets/settings_ui.dart';

/// 设置主页：按大类分组展示设置项，点击进入对应子页。
/// 当前第一组为「外观」；后续新增设置（如播放、存储等）只需在此追加分组。
///
/// 副标题统一用简短说明文字概括功能（如「调整应用外观」），
/// 不展示具体选项摘要；主标题字号大于副标题，形成视觉层级。
class SettingsPage extends StatelessWidget {
  final ThemeController controller;

  const SettingsPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            // 底部预留悬浮胶囊空间（系统安全区已由全局 SafeArea 处理）
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              // ── 第一组：外观 ──────────────────────────────
              const SettingsGroupTitle(title: '外观'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.palette_outlined,
                  title: '外观',
                  subtitle: const Text('调整应用外观'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AppearancePage(controller: controller),
                      ),
                    );
                  },
                ),
              ),
              // ── 播放设置（工作.md 第 6 点：原「播放器」改名）──
              const SettingsGroupTitle(title: '播放设置'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.play_circle_outline,
                  title: '播放设置',
                  subtitle: const Text('调整播放相关设置'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlayerSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
              // ── 媒体扫描与过滤 ────────────────────────────
              const SettingsGroupTitle(title: '媒体库'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.folder_outlined,
                  title: '媒体扫描与过滤',
                  subtitle: const Text('扫描规则与文件夹过滤'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MediaScanSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
              // ── 弹幕（工作.md 第 6 点：弹幕服务器管理）────────
              const SettingsGroupTitle(title: '弹幕'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.dns_outlined,
                  title: '弹幕服务器',
                  subtitle: const Text('网络弹幕服务器与切集自动匹配'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DanmakuServerPage(),
                      ),
                    );
                  },
                ),
              ),
              // ── 其他（后续在此追加更多项）──────────────
              const SettingsGroupTitle(title: '其他'),
              SettingsCard(
                child: SettingsTile(
                  icon: Icons.info_outline,
                  title: '关于',
                  subtitle: const Text('版本信息与工具'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                ),
              ),
              // ── 后续新增设置组示例（按需启用）──────────────
              // const SettingsGroupTitle('播放'),
              // SettingsCard(
              //   child: SettingsTile(
              //     icon: Icons.play_circle_outline,
              //     title: '播放',
              //     onTap: () {},
              //   ),
              // ),
              // const SettingsGroupTitle('存储'),
              // SettingsCard(
              //   child: SettingsTile(
              //     icon: Icons.folder_outlined,
              //     title: '存储',
              //     onTap: () {},
              //   ),
              // ),
            ],
          );
        },
      ),
    );
  }
}
