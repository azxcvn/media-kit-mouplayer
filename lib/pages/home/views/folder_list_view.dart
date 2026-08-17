import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/widgets/folder_card.dart';

/// 列表视图：只列出文件夹（点进去只显示该文件夹内的视频）。
/// 首页列表模式的专属视图。
class FolderListView extends StatelessWidget {
  final List<TreeNode> folders;
  final Set<FolderField> fields;
  final void Function(TreeNode) onFolderTap;

  const FolderListView({
    super.key,
    required this.folders,
    required this.fields,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // 底部预留悬浮胶囊空间（系统安全区已由全局 AppFrame 处理）
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final node = folders[index];
        return FolderCard(
          node: node,
          fields: fields,
          onTap: () => onFolderTap(node),
        );
      },
    );
  }
}
