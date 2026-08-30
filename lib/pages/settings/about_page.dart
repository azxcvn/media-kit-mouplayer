import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:moumou/pages/settings/cache_management_page.dart';
import 'package:moumou/pages/settings/error_log_page.dart';
// 前缀导入：本文件自定义 LicensePage 与 material 内置 LicensePage 同名
import 'package:moumou/pages/settings/license_page.dart' as app;
import 'package:moumou/widgets/settings_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页（设置 → 其他 → 关于）：
/// - 顶部卡片式软件信息（左图标 + 中两行名称/版本 + 右纵排联系图标）；
/// - 「工具」组：缓存管理、错误日志（崩溃日志查看/导出/复制）；
/// - 「信息」组：许可证书（自定义 LicensePage：紧凑卡片头部 + 自动收集全部开源许可）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;

  /// 使用反馈收件邮箱
  static const _feedbackEmail = '2297065843@qq.com';

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
          // ── 顶部卡片：软件信息────────────────────────────
          // 左侧大图标；中间两行（大字名称 + 版本号，宽度视觉接近）；
          // 右缘 GitHub/邮箱 图标纵排。单卡片单行高，紧凑无空洞
          Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 42,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 名称 + 版本：两行左对齐；名称 24sp，视觉宽度与
                  // 下行「版本 v1.0.0」接近
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '小牛Player',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _version == null ? '版本读取中' : '版本 v$_version',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右侧联系图标纵排：GitHub 在上，邮箱在下
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HeaderIconButton(
                        tooltip: 'GitHub',
                        onTap: _openGitHub,
                        child: SvgPicture.asset(
                          'assets/icons/github.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            scheme.onSurfaceVariant,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _HeaderIconButton(
                        tooltip: '发送使用反馈',
                        onTap: _openEmail,
                        child: SvgPicture.asset(
                          'assets/icons/email.svg',
                          width: 20,
                          height: 20,
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
                  subtitle: const Text('查看与清除各类缓存'),
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
                  subtitle: const Text('查看 / 导出 / 复制崩溃日志'),
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    // 前缀引用避免与 Flutter material 内置 LicensePage 冲突
                    builder: (_) => const app.LicensePage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 关于页顶部卡片的纯图标按钮（邮箱 / GitHub 共用样式）：
/// 无底色容器，仅 Tooltip + InkWell 波纹 + 图标，点击区域约 44×44。
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: child,
        ),
      ),
    );
  }
}
