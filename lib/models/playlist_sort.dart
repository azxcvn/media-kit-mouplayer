import 'package:moumou/models/video_file.dart';
import 'package:moumou/utils/natural_compare.dart';

/// 播放列表排序模式（名称 × 升/降序，日期 × 升/降序，共 4 种）。
///
/// 播放列表面板的 4 个排序胶囊直接映射本枚举。
enum PlaylistSortMode {
  nameAsc('名称升序'),
  nameDesc('名称降序'),
  dateAsc('日期升序'),
  dateDesc('日期降序');

  /// 胶囊展示名
  final String label;

  const PlaylistSortMode(this.label);
}

/// 播放列表排序纯函数：返回**新列表**（不改动入参 [videos]）。
///
/// - 名称排序：自然序（[naturalCompare]，数字感知、大小写不敏感），
///   降序即自然序反转；
/// - 日期排序：按 [VideoFile.dateModifiedMs]（毫秒时间戳）比较；
///   未记录修改时间的视频**恒排在末尾**（升序/降序一致），
///   日期相同时按名称自然序升序，保证结果稳定确定。
List<VideoFile> sortVideosForPlaylist(
  List<VideoFile> videos,
  PlaylistSortMode mode,
) {
  final result = [...videos];
  switch (mode) {
    case PlaylistSortMode.nameAsc:
      result.sort((a, b) => naturalCompare(a.name, b.name));
    case PlaylistSortMode.nameDesc:
      result.sort((a, b) => naturalCompare(b.name, a.name));
    case PlaylistSortMode.dateAsc:
      result.sort((a, b) => _compareByDate(a, b, descending: false));
    case PlaylistSortMode.dateDesc:
      result.sort((a, b) => _compareByDate(a, b, descending: true));
  }
  return result;
}

/// 日期主序 + 名称自然序升序的稳定比较。
/// 无日期的视频恒排在末尾（升降序一致：有日期元素永远排在无日期元素之前）；
/// [descending] 只反转日期主序，不反转「无日期垫底」规则。
int _compareByDate(VideoFile a, VideoFile b, {required bool descending}) {
  final da = a.dateModifiedMs;
  final db = b.dateModifiedMs;
  if (da == null || db == null) {
    if (da == db) return naturalCompare(a.name, b.name); // 都无日期 → 按名称
    return da == null ? 1 : -1;
  }
  final cmp = da.compareTo(db);
  if (cmp != 0) return descending ? -cmp : cmp;
  return naturalCompare(a.name, b.name);
}

/// 提取视频文件所在文件夹路径（纯字符串：最后一个 `/` 之前的片段）。
///
/// 视频路径来自 Android MediaStore（POSIX 风格绝对路径，如
/// `/storage/emulated/0/DCIM/xxx.mp4` → `/storage/emulated/0/DCIM`）。
/// 根路径（无 `/`）返回空串。
String folderOfPath(String path) {
  final idx = path.lastIndexOf('/');
  if (idx <= 0) return '';
  return path.substring(0, idx);
}

/// 过滤出 [folder] 目录下的视频（按 [folderOfPath] 比较，纯函数）。
List<VideoFile> filterVideosInFolder(List<VideoFile> videos, String folder) {
  return videos.where((v) => folderOfPath(v.path) == folder).toList();
}
