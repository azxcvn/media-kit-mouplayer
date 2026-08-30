import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/network_connection.dart';

void main() {
  test('NetworkProtocol.tryParse 已知值解析', () {
    expect(NetworkProtocol.tryParse('webdav'), NetworkProtocol.webdav);
    expect(NetworkProtocol.tryParse('smb'), NetworkProtocol.smb);
    expect(NetworkProtocol.tryParse('ftp'), NetworkProtocol.ftp);
    expect(NetworkProtocol.tryParse('nfs'), isNull);
    expect(NetworkProtocol.tryParse(''), isNull);
  });

  test('NetworkProtocol 默认端口', () {
    expect(NetworkProtocol.smb.defaultPort, 445);
    expect(NetworkProtocol.ftp.defaultPort, 21);
    expect(NetworkProtocol.webdav.defaultPort, 80);
  });

  test('NetworkConnection JSON 往返', () {
    const c = NetworkConnection(
      id: 3,
      name: '家庭 NAS',
      protocol: NetworkProtocol.webdav,
      host: 'nas.local',
      port: 5005,
      username: 'bob',
      password: 'secret',
      path: '/movies',
      isAnonymous: false,
      useHttps: true,
      lastConnected: 1690000000000,
    );
    final restored = NetworkConnection.fromJson(c.toJson());
    expect(restored.id, 3);
    expect(restored.name, '家庭 NAS');
    expect(restored.protocol, NetworkProtocol.webdav);
    expect(restored.host, 'nas.local');
    expect(restored.port, 5005);
    expect(restored.username, 'bob');
    expect(restored.password, 'secret');
    expect(restored.path, '/movies');
    expect(restored.isAnonymous, isFalse);
    expect(restored.useHttps, isTrue);
    expect(restored.lastConnected, 1690000000000);
  });

  test('NetworkConnection.fromJson 字段缺失容错', () {
    final c = NetworkConnection.fromJson(const {});
    expect(c.id, 0);
    expect(c.name, '未命名');
    expect(c.protocol, NetworkProtocol.webdav);
    expect(c.host, '');
    expect(c.port, NetworkProtocol.webdav.defaultPort);
    expect(c.path, '/');
  });

  test('copyWith 局部覆盖', () {
    const c = NetworkConnection(name: 'a', protocol: NetworkProtocol.ftp, host: 'h', port: 21);
    final c2 = c.copyWith(name: 'b', id: 9);
    expect(c2.name, 'b');
    expect(c2.id, 9);
    expect(c2.host, 'h');
    expect(c2.protocol, NetworkProtocol.ftp);
  });

  test('toString 不泄露凭据', () {
    const c = NetworkConnection(
      name: 'a',
      protocol: NetworkProtocol.ftp,
      host: 'h',
      port: 21,
      password: 'topsecret',
    );
    expect(c.toString(), isNot(contains('topsecret')));
    expect(c.toString(), contains('credentials=<redacted>'));
  });
}