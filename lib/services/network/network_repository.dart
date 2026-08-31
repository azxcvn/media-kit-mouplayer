/// 网络存储上层操作入口（对齐 mpvRx `NetworkRepository` 的分层，但按需精简）：
/// 浏览目录、以及把远端文件注册为本地 loopback 播放 URL。
library;

import 'package:moumou/models/network_connection.dart';
import 'package:moumou/models/network_file.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/services/network/network_client_factory.dart';
import 'package:moumou/services/network/network_streaming_proxy.dart';

class NetworkRepository {
  NetworkRepository._();

  static final NetworkRepository instance = NetworkRepository._();

  /// 连接并列出 [path] 下的内容（用完即断开）。
  Future<List<NetworkFile>> browse(NetworkConnection connection, String path) async {
    // Android 16+ 本地网络保护：连局域网 NAS 前先请求权限（缺失会被系统拦截）
    await DeviceServices.requestLocalNetworkPermission();
    final client = createNetworkClient(connection);
    try {
      await client.connect();
      return await client.listFiles(path);
    } finally {
      await client.disconnect();
    }
  }

  /// 注册播放流，返回无凭据 loopback URL（供 PlayerPage 直接播放）。
  Future<String> playbackUrl(
    NetworkConnection connection,
    String path, {
    int fileSize = -1,
    String mimeType = 'video/mp4',
  }) {
    return NetworkStreamingProxy.instance.registerStream(
      connection,
      path,
      fileSize: fileSize,
      mimeType: mimeType,
    );
  }

  /// 释放播放流（播放页关闭后由界面侧调用）。
  Future<void> releasePlayback(String url) {
    return NetworkStreamingProxy.instance.unregisterStream(url);
  }
}