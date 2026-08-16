import 'package:moumou/models/video_file.dart';

/// 树节点类型
enum TreeNodeType { folder, video }

/// 目录树节点：folder 节点可展开，video 节点为叶子
class TreeNode {
  final String name;
  final String path; // folder = 目录路径；video = 文件路径
  final TreeNodeType type;
  final VideoFile? video; // 仅 video 节点有值
  final List<TreeNode> children; // 仅 folder 节点有值

  // folder 节点聚合信息（含所有子目录）
  final int videoCount;
  final int totalSize;
  final DateTime? dateModified;

  const TreeNode({
    required this.name,
    required this.path,
    required this.type,
    this.video,
    this.children = const [],
    this.videoCount = 0,
    this.totalSize = 0,
    this.dateModified,
  });

  bool get isFolder => type == TreeNodeType.folder;
}
