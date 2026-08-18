import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 自定义许可证书页（设置 → 关于 → 许可证书）：
/// - 紧凑卡片式头部：小图标 + 应用名 + 版本号 水平排列，尾部显示许可数量角标；
/// - 下方为 LicenseRegistry 自动收集的全部开源许可列表（每包一行，点击展开全文），
///   样式全部跟随主题色（primaryContainer / primary / surfaceContainerLow 等）。
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
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                _LicenseEntryCard(package: package, entry: map[package]!),
            ],
          );
        },
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

/// 单个包的开源许可条目：收起时仅一行包名，展开后显示完整许可文本（可选中复制）。
class _LicenseEntryCard extends StatelessWidget {
  final String package;
  final LicenseEntry entry;

  const _LicenseEntryCard({required this.package, required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final licenseText = entry.paragraphs.map((p) => p.text).join('\n\n');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // 去掉展开/收起状态下的分隔线，保持卡片一体
        shape: const Border(),
        collapsedShape: const Border(),
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
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              licenseText,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
