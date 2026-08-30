/// 网络共享上的单个文件或目录（对齐 mpvRx 的 NetworkFile）。
library;

class NetworkFile {
  final String name;
  final String path; // 相对连接根的规范化路径（以 / 开头）
  final int size; // 字节；目录或未知为 -1
  final bool isDirectory;
  final int lastModified; // 毫秒时间戳，0 表示未知
  final String? mimeType;

  const NetworkFile({
    required this.name,
    required this.path,
    this.size = -1,
    this.isDirectory = false,
    this.lastModified = 0,
    this.mimeType,
  });
}