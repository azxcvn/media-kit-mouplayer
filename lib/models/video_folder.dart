/// 视频文件夹模型
class VideoFolder {
  final String name; // 文件夹名
  final String path; // 文件夹绝对路径
  final int videoCount; // 文件夹内视频数量
  final String? coverPath; // 封面图路径（后续做缩略图用）

  const VideoFolder({
    required this.name,
    required this.path,
    required this.videoCount,
    this.coverPath,
  });
}
