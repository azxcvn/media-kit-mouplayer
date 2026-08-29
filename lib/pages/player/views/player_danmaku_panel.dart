/// 弹幕二级界面（播放器「更多 → 弹幕」/ 顶栏「弹幕」槽位共用，阶段1）：
/// 四个入口——本地弹幕（文件选择器导入，已实现）/ 网络弹幕（待上线）/
/// 自动匹配（待上线）/ 弹幕设置（与底栏弹幕设置按钮同一行为）。
///
/// 本地弹幕的文件选择器**规则与参数风格与本地字幕文件选择器一致**（工作.md
/// 弹幕第 2 点）：
/// - SDK ≤ 30：系统文件选择器（ACTION_OPEN_DOCUMENT），content:// 由原生侧
///   拷贝到 filesDir/danmaku/ 后返回真实路径；
/// - SDK ≥ 31：复用自建选择器面板 [SubtitleFilePickerPanel]（只换文件过滤
///   器 / 图标 / 记忆键，对齐音频选择器的复用方式，§4.5「不得另写一套外壳」），
///   支持排序与文件夹记忆（独立记忆键）。
///
/// 网络弹幕 / 自动匹配 / 弹幕设置以 toast 提示待上线（阶段1 只铺基础设施）。
library;

import 'package:flutter/material.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/danmaku_service.dart';
import 'package:moumou/pages/player/views/subtitle_file_picker.dart';
import 'package:moumou/utils/danmaku_local_file.dart';
import 'package:moumou/widgets/player_panel.dart';

/// 本地弹幕文件选择服务（对齐 [SubtitleFileService] / AudioFileService 的思路）。
///
/// - SDK ≤ 30：系统选择器（content:// 由原生侧拷贝为真实路径）；
/// - SDK ≥ 31：复用自建选择器（[SubtitleFilePickerPanel]，独立记忆文件夹）。
class DanmakuFileService {
  DanmakuFileService._();

  static const lastFolderKey = 'danmaku_picker_last_folder';

  /// 系统文件选择器（Android ≤ 11）：content:// 拷贝为应用内真实路径后返回。
  static Future<String?> pickWithSystemPicker() async {
    final uri = await DeviceServices.openDocumentPicker();
    if (uri == null) return null;
    final name = uri.split('/').where((s) => s.isNotEmpty).last;
    final fileName = name.isEmpty ? 'danmaku.xml' : name;
    return DeviceServices.copyDanmakuFromUri(uri, fileName);
  }
}

class PlayerDanmakuPanel extends StatelessWidget {
  /// 弹幕控制器（横竖屏共享同一实例）
  final DanmakuController controller;

  /// 打开弹幕设置（与底栏弹幕设置按钮**同一回调**：两种入口进入同一设置）
  final VoidCallback onSettingsTap;

  /// 面板内二级页就地切换（由页面注入：横屏传 PlayerPanelNavigator、
  /// 竖屏传 PlayerBottomPanelNavigator，面板不直接依赖外壳）
  final void Function(String title, Widget body)? onPushSubPage;

  /// 选择器二级页返回（由页面注入）
  final VoidCallback? onPopSubPage;

  const PlayerDanmakuPanel({
    super.key,
    required this.controller,
    required this.onSettingsTap,
    this.onPushSubPage,
    this.onPopSubPage,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _DanmakuOptionTile(
          icon: Icons.file_open_outlined,
          label: '本地弹幕',
          onTap: () => _importLocalDanmaku(context),
        ),
        _DanmakuOptionTile(
          icon: Icons.cloud_outlined,
          label: '网络弹幕',
          onTap: () => _toast(context, '「网络弹幕」功能即将上线'),
        ),
        _DanmakuOptionTile(
          icon: Icons.auto_fix_high,
          label: '自动匹配',
          onTap: () => _toast(context, '「自动匹配」功能即将上线'),
        ),
        _DanmakuOptionTile(
          icon: Icons.settings_outlined,
          label: '弹幕设置',
          onTap: onSettingsTap,
        ),
      ],
    );
  }

  // ── 本地弹幕导入（文件选择器，规则对齐本地字幕文件选择器）──

  /// 面板内二级页就地切换（§4.5：复用面板导航器，禁止叠加第二个面板）。
  void _pushSubPage(BuildContext context, String title, Widget body) {
    final push = onPushSubPage;
    if (push != null) {
      push(title, body);
      return;
    }
    // 兜底：无注入时尝试右侧面板导航器（横屏外壳）
    PlayerPanelNavigator.of(context)
        .push(PlayerPanelPage(title: title, body: body));
  }

  /// 导入本地弹幕：按 Android 版本走系统/自建文件选择器。
  /// - SDK ≤ 30：系统选择器（原生 ACTION_OPEN_DOCUMENT）；
  /// - SDK ≥ 31：自建选择器（复用 [SubtitleFilePickerPanel]，面板二级页）。
  Future<void> _importLocalDanmaku(BuildContext context) async {
    final sdk = await DeviceServices.getSdkInt();
    if (!context.mounted || sdk <= 0) return;
    if (sdk <= 30) {
      final path = await DanmakuFileService.pickWithSystemPicker();
      if (path == null || !context.mounted) return;
      await _loadPickedFile(context, path);
      return;
    }
    // 自建选择器：作为面板二级页就地切换（复用字幕文件选择器外壳，
    // 只换文件过滤器/图标/记忆键——与音频选择器同款复用方式）
    _pushSubPage(
      context,
      '选择弹幕文件',
      SubtitleFilePickerPanel(
        fileFilter: isSupportedDanmakuFile,
        folderKey: DanmakuFileService.lastFolderKey,
        fileIcon: Icons.comment_outlined,
        onPicked: (path) async {
          await _loadPickedFile(context, path);
        },
        onClose: () => onPopSubPage?.call(),
      ),
    );
  }

  /// 加载所选弹幕文件并给出轻提示（成功带条数；空文件/解析失败视为失败）
  Future<void> _loadPickedFile(BuildContext context, String path) async {
    final ok = await controller.loadDanmakuFromFile(path);
    if (!context.mounted) return;
    _toast(
      context,
      ok ? '已加载本地弹幕（${controller.danmakuCount} 条）' : '弹幕加载失败，请检查文件格式',
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// 弹幕二级界面的选项行：图标 + 名称 + 箭头（样式对齐「更多」面板的动作行）。
class _DanmakuOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DanmakuOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      titleAlignment: ListTileTitleAlignment.center,
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}
