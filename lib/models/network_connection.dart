/// 网络存储协议枚举与连接（账号）配置模型。
library;

/// 支持的远程协议（对齐 mpvRx 的 NetworkProtocol）
enum NetworkProtocol {
  smb('SMB', 445),
  ftp('FTP', 21),
  webdav('WebDAV', 80);

  final String displayName;
  final int defaultPort;
  const NetworkProtocol(this.displayName, this.defaultPort);

  /// 按持久化用的字符串名反查（未知值返回 null，调用方决定兜底）
  static NetworkProtocol? tryParse(String value) {
    for (final p in NetworkProtocol.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// 一条网络连接（账号）配置。纯数据，可 json 序列化。
class NetworkConnection {
  final int id; // 本地自增 id（0 = 尚未入库）
  final String name;
  final NetworkProtocol protocol;
  final String host;
  final int port;
  final String username;
  final String password;
  final String path; // 根路径，默认 '/'
  final bool isAnonymous;
  final bool useHttps; // 仅 WebDAV
  final int lastConnected; // 最近连接时间戳（毫秒）

  const NetworkConnection({
    this.id = 0,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.path = '/',
    this.isAnonymous = false,
    this.useHttps = false,
    this.lastConnected = 0,
  });

  NetworkConnection copyWith({
    int? id,
    String? name,
    NetworkProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
    String? path,
    bool? isAnonymous,
    bool? useHttps,
    int? lastConnected,
  }) {
    return NetworkConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      useHttps: useHttps ?? this.useHttps,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'path': path,
        'isAnonymous': isAnonymous,
        'useHttps': useHttps,
        'lastConnected': lastConnected,
      };

  /// 容错解析：字段缺失/类型不符时回退默认值，损坏单条不拖垮整个列表。
  factory NetworkConnection.fromJson(Map<String, dynamic> json) {
    return NetworkConnection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '未命名',
      protocol:
          NetworkProtocol.tryParse(json['protocol'] as String? ?? '') ??
              NetworkProtocol.webdav,
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? NetworkProtocol.webdav.defaultPort,
      username: (json['username'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      path: (json['path'] as String?) ?? '/',
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      useHttps: (json['useHttps'] as bool?) ?? false,
      lastConnected: (json['lastConnected'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'NetworkConnection(id=$id, name=$name, protocol=$protocol, credentials=<redacted>)';
}