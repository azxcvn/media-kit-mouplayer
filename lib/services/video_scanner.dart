import 'dart:io';

import 'package:moumou/models/video_file.dart';
import 'package:moumou/models/video_folder.dart';

/// 视频扫描器：扫描本地视频并支持按文件夹分组
class VideoScanner {
  static const List<String> videoExt = [
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.ts',
    '.m4v', '.webm', '.3gp', '.mpg', '.mpeg',
  ];

  /// 扫描的根目录（后续可换成 MediaStore）
  static const List<String> roots = [
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Video',
  ];

  /// 扫描所有视频文件
  static Future<List<VideoFile>> scanVideos() async {
    final result = <String, VideoFile>{};

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (videoExt.any((ext) => lower.endsWith(ext))) {
          result[entity.path] = VideoFile(
            path: entity.path,
            name: entity.path.split('/').last,
          );
        }
      }
    }

    final list = result.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// 按父文件夹分组，返回文件夹列表（按视频数量降序）
  static Future<List<VideoFolder>> scanFolders() async {
    final videos = await scanVideos();
    final map = <String, List<VideoFile>>{};

    for (final v in videos) {
      final dir = v.path.contains('/')
          ? v.path.substring(0, v.path.lastIndexOf('/'))
          : '/';
      map.putIfAbsent(dir, () => []).add(v);
    }

    final folders = map.entries.map((e) {
      final path = e.key;
      final name = path.contains('/')
          ? path.substring(path.lastIndexOf('/') + 1)
          : path;
      return VideoFolder(
        name: name,
        path: path,
        videoCount: e.value.length,
      );
    }).toList()
      ..sort((a, b) => b.videoCount.compareTo(a.videoCount));

    return folders;
  }
}
