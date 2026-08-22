import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 自定义许可证书页（设置 → 关于 → 许可证书，工作.md 第 7 点重做）：
/// - 不再使用折叠式（ExpansionTile）：改为**列表 + 二级详情页**——
///   每个包一行（图标 + 包名 + 许可数量 + 箭头），点击进入该包的许可详情页；
/// - 顶部保留紧凑卡片式头部：小图标 + 应用名 + 版本号 水平排列 + 许可数量角标；
/// - 详情页展示完整许可文本（可选中复制），带一键复制按钮。
class LicensePage extends StatefulWidget {
  const LicensePage({super.key});

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  late Future<Map<String, LicenseEntry>> _licensesFuture;
  String? _version;

  /// `LicenseRegistry.licenses` 是 `Stream<LicenseEntry>`；本 SDK 的
  /// LicenseRegistry 没有 collectLicenses()，这里手动把流一次性收集为
  /// `Future<Map<String, LicenseEntry>>`（包名 → 许可条目），配合 FutureBuilder
  /// 整页渲染，避免每个许可单独建流监听。
  static Future<Map<String, LicenseEntry>> _collectLicenses() async {
    final map = <String, LicenseEntry>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        map[package] = entry;
      }
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _licensesFuture = _collectLicenses();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) setState(() => _version = info.version);
        })
        .catchError((_) {});
  }

  void _reload() {
    setState(() => _licensesFuture = _collectLicenses());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('许可证书')),
      body: FutureBuilder<Map<String, LicenseEntry>>(
        future: _licensesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(onRetry: _reload);
          }
          final map = snapshot.data;
          if (map == null || map.isEmpty) {
            return Center(
              child: Text(
                '暂无许可信息',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          // 按包名排序（忽略大小写），保持列表稳定有序
          final packages = map.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _LicenseHeaderCard(
                version: _version,
                licenseCount: packages.length,
              ),
              const SizedBox(height: 20),
              const SettingsGroupTitle(title: '开源许可'),
              for (final package in packages)
                _LicenseEntryTile(
                  package: package,
                  entry: map[package]!,
                  onTap: () => _openDetail(package, map[package]!),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(String package, LicenseEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LicenseDetailPage(package: package, entry: entry),
      ),
    );
  }
}

/// 紧凑卡片式头部：水平排列 小图标 + 应用名 + 版本号，尾部为许可数量角标。
class _LicenseHeaderCard extends StatelessWidget {
  final String? version;
  final int licenseCount;

  const _LicenseHeaderCard({required this.version, required this.licenseCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // 小图标（主题色容器）
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 26,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            // 名称 + 版本号：同一水平基线，紧凑排布
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    '小牛Player',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      version == null ? '版本读取中…' : 'v$version',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 尾部：许可数量角标
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$licenseCount 项许可',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个包的一行入口：图标 + 包名 + 许可段落数 + 右箭头；点击进入详情页。
class _LicenseEntryTile extends StatelessWidget {
  final String package;
  final LicenseEntry entry;
  final VoidCallback onTap;

  const _LicenseEntryTile({
    required this.package,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.code_rounded,
            size: 18,
            color: scheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          package,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${entry.paragraphs.length} 个许可段落',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

/// 许可证书详情页（二级界面）：完整许可文本 + 一键复制。
class LicenseDetailPage extends StatelessWidget {
  final String package;
  final LicenseEntry entry;

  const LicenseDetailPage({
    super.key,
    required this.package,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final licenseText = entry.paragraphs.map((p) => p.text).join('\n\n');
    return Scaffold(
      appBar: AppBar(
        title: Text(package, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '复制许可文本',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: licenseText));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('许可文本已复制'),
                    duration: Duration(milliseconds: 1200),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部摘要卡片：包名 + 许可段落数
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${entry.paragraphs.length} 个许可段落',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 完整许可文本（可选中复制）
            SelectableText(
              licenseText,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 许可收集失败时的错误视图（带重试）
class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            '许可信息加载失败',
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
