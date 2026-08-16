import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/formatters.dart';
import 'package:moumou/widgets/marquee_text.dart';

/// 文件夹卡片：列表模式与树状模式共用（字段驱动渲染）
///
/// 尾部为静态 chevron_right，点击进入下一层（列表=文件夹详情页；树状=目录浏览页）。
class FolderCard extends StatelessWidget {
  final TreeNode node;
  final Set<FolderField> fields;
  final VoidCallback onTap;

  const FolderCard({
    super.key,
    required this.node,
    required this.fields,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      text: node.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._buildFields(scheme),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFields(ColorScheme scheme) {
    final widgets = <Widget>[];

    // 路径：单独一行（长文本，超长省略不换行）
    if (fields.contains(FolderField.path)) {
      widgets.add(_fieldRow(scheme, Icons.folder_open, node.path));
    }

    // 数量/大小/日期：横向紧凑排列
    final tags = <Widget>[];
    if (fields.contains(FolderField.count)) {
      tags.add(
        _fieldTag(
          scheme,
          Icons.video_library_outlined,
          '${node.videoCount} 个视频',
        ),
      );
    }
    if (fields.contains(FolderField.size)) {
      tags.add(
        _fieldTag(scheme, Icons.data_usage, formatFileSize(node.totalSize)),
      );
    }
    if (fields.contains(FolderField.date)) {
      tags.add(
        _fieldTag(
          scheme,
          Icons.calendar_today_outlined,
          formatDate(node.dateModified),
        ),
      );
    }
    if (tags.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 14, runSpacing: 4, children: tags),
        ),
      );
    }

    return widgets;
  }

  Widget _fieldRow(ColorScheme scheme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldTag(ColorScheme scheme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
