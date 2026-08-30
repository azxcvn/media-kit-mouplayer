/// 按协议枚举创建对应客户端（对齐 mpvRx 的 `NetworkClientFactory`）。
library;

import 'package:moumou/models/network_connection.dart';
import 'package:moumou/services/network/ftp_client.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/services/network/smb_client.dart';
import 'package:moumou/services/network/webdav_client.dart';

NetworkClient createNetworkClient(NetworkConnection connection) {
  switch (connection.protocol) {
    case NetworkProtocol.smb:
      return SmbClient(connection);
    case NetworkProtocol.ftp:
      return FtpClient(connection);
    case NetworkProtocol.webdav:
      return WebDavClient(connection);
  }
}