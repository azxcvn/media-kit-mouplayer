import 'package:flutter/services.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/services/media_scan_settings.dart';

/// 视频扫描器：通过原生 MediaStore 查询视频，并构建完整目录树
class VideoScanner {
  static const MethodChannel _channel = MethodChannel('moumou/video_info');

  /// 内存缓存：避免首页和详情页重复查询 MediaStore
  static List<VideoFile>? _cachedVideos;

  static const List<String> videoExt = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.ts',
    '.m4v',
    '.webm',
    '.3gp',
    '.mpg',
    '.mpeg',
  ];

  /// 清除内存缓存（下拉刷新时调用）
  static void clearCache() {
    _cachedVideos = null;
  }

  /// 查询所有本地视频（结合 MediaScanSettings 的 .nomedia、隐藏文件夹及黑白名单规则）
  static Future<List<VideoFile>> scanVideos({
    MediaScanSettings? scanSettings,
  }) async {
    if (_cachedVideos != null) return _cachedVideos!;

    final settings = scanSettings ?? MediaScanSettings.instance;
    await settings.ensureLoaded();

    final result = await _channel.invokeListMethod<dynamic>(
      'getVideos',
      {
        'includeNoMedia': settings.scanNoMedia,
        'includeHidden': settings.scanHiddenFolders,
      },
    );
    if (result == null) return [];

    final videos = <VideoFile>[];
    for (final item in result) {
      final map = Map<String, dynamic>.from(item as Map);
      final path = map['path'] as String? ?? '';
      if (path.isEmpty) continue;

      // 应用黑名单 / 白名单过滤规则
      if (!settings.isPathAllowed(path)) {
        continue;
      }

      final dateModifiedMs = (map['dateModifiedMs'] as num?)?.toInt();
      videos.add(
        VideoFile(
          path: path,
          name: map['name'] as String? ?? '',
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
          size: (map['size'] as num?)?.toInt() ?? 0,
          width: (map['width'] as num?)?.toInt() ?? 0,
          height: (map['height'] as num?)?.toInt() ?? 0,
          dateModified: dateModifiedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(dateModifiedMs)
              : null,
        ),
      );
    }

    videos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cachedVideos = videos;
    return videos;
  }

  /// 构建完整目录树：从存储卷根开始，包含中间目录（只含子文件夹的目录
  /// 也会保留），并递归聚合每个文件夹的视频数量 / 总大小 / 最新修改时间。
  ///
  /// 顶层节点 = 各存储卷根下的直接子目录（folder）与直接视频（video）。
  static List<TreeNode> buildTree(List<VideoFile> videos) {
    if (videos.isEmpty) return [];

    final root = _TreeBuilder.root();
    for (final v in videos) {
      final dir = _dirOf(v.path);
      final segs = dir.split('/').where((s) => s.isNotEmpty).toList();
      final rootSegs = _rootSegCount(segs);

      if (rootSegs <= 0) {
        // 无法识别存储根：直接作为顶层视频
        root.videos.add(v);
        continue;
      }

      final rootPath = '/${segs.sublist(0, rootSegs).join('/')}';
      var node = root;
      var pathSoFar = rootPath;
      for (var i = rootSegs; i < segs.length; i++) {
        pathSoFar = '$pathSoFar/${segs[i]}';
        node = node.childFolder(segs[i], pathSoFar);
      }
      node.videos.add(v);
    }

    final nodes = <TreeNode>[];
    for (final f in root.folders.values) {
      nodes.add(f.toTreeNode());
    }
    for (final v in root.videos) {
      nodes.add(
        TreeNode(
          name: v.name,
          path: v.path,
          type: TreeNodeType.video,
          video: v,
        ),
      );
    }
    // 文件夹在前、视频在后，各按名称升序
    nodes.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  /// 列表模式：按视频「直接父目录」分组，返回所有含直接视频的文件夹。
  /// 每个文件夹的 children 只含它的直接视频，videoCount 为直接视频数。
  static List<TreeNode> buildFolderList(List<VideoFile> videos) {
    final map = <String, List<VideoFile>>{};
    for (final v in videos) {
      map.putIfAbsent(_dirOf(v.path), () => []).add(v);
    }

    final folders = <TreeNode>[];
    for (final e in map.entries) {
      final path = e.key;
      final name = path.contains('/')
          ? path.substring(path.lastIndexOf('/') + 1)
          : path;

      var totalSize = 0;
      DateTime? modified;
      final videoChildren = <TreeNode>[];
      for (final v in e.value) {
        totalSize += v.size;
        if (modified == null ||
            (v.dateModified != null && v.dateModified!.isAfter(modified))) {
          modified = v.dateModified;
        }
        videoChildren.add(
          TreeNode(
            name: v.name,
            path: v.path,
            type: TreeNodeType.video,
            video: v,
          ),
        );
      }

      folders.add(
        TreeNode(
          name: name,
          path: path,
          type: TreeNodeType.folder,
          children: videoChildren,
          videoCount: e.value.length,
          totalSize: totalSize,
          dateModified: modified,
        ),
      );
    }

    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return folders;
  }

  /// 从视频绝对路径取父目录
  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  /// 识别存储卷根占用的段数：
  /// - /storage/emulated/0 → 3 段
  /// - /storage/XXXX-XXXX → 2 段（SD 卡 / U 盘）
  /// - 其他 → 0（无法识别）
  static int _rootSegCount(List<String> segs) {
    if (segs.length >= 3 && segs[0] == 'storage' && segs[1] == 'emulated') {
      return 3;
    }
    if (segs.length >= 2 && segs[0] == 'storage') {
      return 2;
    }
    return 0;
  }
}

/// 构建树用的可变节点
class _TreeBuilder {
  final String name;
  final String path;
  final Map<String, _TreeBuilder> folders = {};
  final List<VideoFile> videos = [];

  _TreeBuilder({required this.name, required this.path});

  static _TreeBuilder root() => _TreeBuilder(name: '', path: '');

  _TreeBuilder childFolder(String name, String path) {
    return folders.putIfAbsent(
      path,
      () => _TreeBuilder(name: name, path: path),
    );
  }

  TreeNode toTreeNode() {
    final children = <TreeNode>[];

    for (final f in folders.values) {
      children.add(f.toTreeNode());
    }
    for (final v in videos) {
      children.add(
        TreeNode(
          name: v.name,
          path: v.path,
          type: TreeNodeType.video,
          video: v,
        ),
      );
    }
    // 文件夹在前、视频在后，各按名称升序
    children.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // 递归聚合：视频总数 / 总大小 / 最新修改时间
    var count = 0;
    var size = 0;
    DateTime? modified;
    for (final c in children) {
      if (c.type == TreeNodeType.video) {
        count++;
        size += c.video!.size;
        if (c.video!.dateModified != null &&
            (modified == null || c.video!.dateModified!.isAfter(modified))) {
          modified = c.video!.dateModified;
        }
      } else {
        count += c.videoCount;
        size += c.totalSize;
        if (c.dateModified != null &&
            (modified == null || c.dateModified!.isAfter(modified))) {
          modified = c.dateModified;
        }
      }
    }

    return TreeNode(
      name: name,
      path: path,
      type: TreeNodeType.folder,
      children: children,
      videoCount: count,
      totalSize: size,
      dateModified: modified,
    );
  }
}
