import 'package:flutter/material.dart';
import 'package:moumou/pages/settings/cache_management_page.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 关于页（设置 → 其他 → 关于）：应用信息 + 工具组。
/// 工具组后续还会引入其他工具（如日志、导入导出等），在此追加。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) setState(() => _version = info.version);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          // ── 应用信息 ──────────────────────────────
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 44,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '小牛Player',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _version == null ? '版本信息读取中…' : '版本 v$_version',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          // ── 工具组（未来继续追加工具入口）──────────
          const SettingsGroupTitle(title: '工具'),
          SettingsCard(
            child: SettingsTile(
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
          ),
        ],
      ),
    );
  }
}
