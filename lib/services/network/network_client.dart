/// 网络协议客户端统一接口（对齐 mpvRx 的 `NetworkClient` 思路）。
///
/// 客户端生命周期由调用方管理：先 [connect]，再 [listFiles] /
/// [getFileSize] / [openStream]，最后 [disconnect]。方法失败统一抛
/// [NetworkClientException]，message 面向用户展示且不含任何凭据。
library;

import 'package:moumou/models/network_file.dart';

/// 网络协议通用错误。
class NetworkClientException implements Exception {
  final String message;
  const NetworkClientException(this.message);

  @override
  String toString() => message;
}

/// 所有远程协议（WebDAV / SMB / FTP）客户端的统一抽象。
abstract class NetworkClient {
  /// 连接并完成认证；失败抛 [NetworkClientException]。
  Future<void> connect();

  /// 释放连接（幂等，可重复调用）。
  Future<void> disconnect();

  /// 当前是否已连接。
  bool isConnected();

  /// 列出 [path] 下的文件与目录（[path] 为连接根下的规范化路径，`/` 为根）。
  Future<List<NetworkFile>> listFiles(String path);

  /// 获取文件大小（字节）。无法确定时返回 -1（不抛异常，交由上层降级）；
  /// 仅在与服务器交互等致命错误时抛 [NetworkClientException]。
  Future<int> getFileSize(String path);

  /// 打开文件字节流，从 [offset] 字节处开始。返回的流关闭时释放底层连接。
  Future<Stream<List<int>>> openStream(String path, {int offset = 0});
}