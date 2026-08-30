/// 视频来源：本地媒体库 或 远程网络存储（WebDAV/SMB/FTP）。
enum VideoSource { local, network }

/// 视频文件模型
class VideoFile {
  final String path; // 本地=绝对路径；网络=远程相对路径（连接根下）
  final String name; // 文件名
  final int durationMs; // 时长（毫秒）
  final int size; // 文件大小（字节）
  final int width; // 分辨率宽
  final int height; // 分辨率高
  final DateTime? dateModified; // 修改时间

  // ── 网络来源扩展（本地视频取默认值，不破坏现有本地链路）────────
  final VideoSource source; // 默认 local
  final String? remotePath; // 网络远程相对路径（本地为 null）
  final int? connectionId; // 网络连接 id（本地为 null）

  const VideoFile({
    required this.path,
    required this.name,
    this.durationMs = 0,
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.dateModified,
    this.source = VideoSource.local,
    this.remotePath,
    this.connectionId,
  });

  /// 修改时间（毫秒时间戳）；未记录时为 null（播放列表日期排序用）
  int? get dateModifiedMs => dateModified?.millisecondsSinceEpoch;
}
