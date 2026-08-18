import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:moumou/pages/settings/cache_management_page.dart';
import 'package:moumou/pages/settings/error_log_page.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页（设置 → 其他 → 关于）：
/// - 顶部卡片式软件信息（横向：左侧 icon 放大、中间 名称+版本 纵向、右侧 邮箱/GitHub 图标）；
/// - 「工具」组：缓存管理、错误日志（崩溃日志查看/导出/复制）；
/// - 「信息」组：许可证书（LicensePage 自动收集全部开源许可）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;

  /// 使用反馈收件邮箱
  static const _feedbackEmail = '2297065843@qq.ccom';

  /// GitHub 主页地址（暂时留空，后续接入）
  static const _githubUrl = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) setState(() => _version = info.version);
        })
        .catchError((_) {});
  }

  /// 跳转手机邮件并进入写邮件界面（收件人 + 主题「播放器使用反馈」）
  Future<void> _openEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _feedbackEmail,
      query: 'subject=${Uri.encodeComponent('播放器使用反馈')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _toast('未找到可用的邮件应用');
    }
  }

  /// 跳转浏览器访问 GitHub（地址暂时留空，接入前提示）
  Future<void> _openGitHub() async {
    if (_githubUrl.isEmpty) {
      _toast('GitHub 主页地址待接入');
      return;
    }
    final uri = Uri.parse(_githubUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _toast('无法打开链接');
    }
  }

  void _toast(String message) {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          const SizedBox(height: 8),
          // ── 顶部卡片：软件信息（横向）──────────────────
          Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
              child: Row(
                children: [
                  // 左侧：icon 整体放大
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 中间：名称 + 版本（纵向排列，上名字下版本）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '小牛Player',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _version == null ? '版本信息读取中…' : '版本 v$_version',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧：邮箱（上）/ GitHub（下），纵向排列
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _HeaderIconButton(
                        tooltip: '发送使用反馈',
                        onTap: _openEmail,
                        child: SvgPicture.asset(
                          'assets/icons/email.svg',
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            scheme.onSurfaceVariant,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _HeaderIconButton(
                        tooltip: 'GitHub',
                        onTap: _openGitHub,
                        child: SvgPicture.asset(
                          'assets/icons/github.svg',
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            scheme.onSurfaceVariant,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ── 工具组 ──────────────────────────────────────
          const SettingsGroupTitle(title: '工具'),
          SettingsCard(
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.cleaning_services_outlined,
                  title: '缓存管理',
                  subtitle: const Text('查看与清除各类缓存（缩略图等）'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CacheManagementPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SettingsTile(
                  icon: Icons.receipt_long_outlined,
                  title: '错误日志',
                  subtitle: const Text('崩溃日志自动记录，支持查看 / 导出 / 复制'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ErrorLogPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── 信息组 ──────────────────────────────────────
          const SettingsGroupTitle(title: '信息'),
          SettingsCard(
            child: SettingsTile(
              icon: Icons.gavel_outlined,
              title: '许可证书',
              subtitle: const Text('查看本应用使用的全部开源许可'),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: '小牛Player',
                  applicationVersion: _version == null ? '' : 'v$_version',
                  applicationLegalese: '开源许可证',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 关于页顶部卡片的圆形图标按钮（邮箱 / GitHub 共用样式）
class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _HeaderIconButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
