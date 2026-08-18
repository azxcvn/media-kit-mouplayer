/// 视频文件模型
class VideoFile {
  final String path; // 绝对路径
  final String name; // 文件名
  final int durationMs; // 时长（毫秒）
  final int size; // 文件大小（字节）
  final int width; // 分辨率宽
  final int height; // 分辨率高
  final DateTime? dateModified; // 修改时间

  const VideoFile({
    required this.path,
    required this.name,
    this.durationMs = 0,
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.dateModified,
  });

  /// 修改时间（毫秒时间戳）；未记录时为 null（播放列表日期排序用）
  int? get dateModifiedMs => dateModified?.millisecondsSinceEpoch;
}
