import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/network_connection.dart';
import 'package:moumou/services/network/network_connection_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkConnectionSettings.instance.reset();
  });

  test('初始为空', () {
    expect(NetworkConnectionSettings.instance.connections, isEmpty);
  });

  test('add 分配自增 id 并持久化', () async {
    final s = NetworkConnectionSettings.instance;
    final a = await s.add(const NetworkConnection(
      name: 'NAS',
      protocol: NetworkProtocol.webdav,
      host: '192.168.1.2',
      port: 5005,
    ));
    final b = await s.add(const NetworkConnection(
      name: 'FTP',
      protocol: NetworkProtocol.ftp,
      host: 'ftp.example.com',
      port: 21,
    ));
    expect(a.id, 1);
    expect(b.id, 2);
    expect(s.connections.length, 2);

    // 模拟重启：reset 清内存，load 从 prefs 恢复
    s.reset();
    await s.load();
    expect(s.connections.length, 2);
    expect(s.connections.map((c) => c.name), containsAll(['NAS', 'FTP']));
  });

  test('update 按 id 替换', () async {
    final s = NetworkConnectionSettings.instance;
    final a = await s.add(const NetworkConnection(
      name: 'NAS',
      protocol: NetworkProtocol.smb,
      host: 'h',
      port: 445,
    ));
    await s.update(a.copyWith(name: 'NAS2', port: 9000));
    expect(s.connections.single.name, 'NAS2');
    expect(s.connections.single.port, 9000);
  });

  test('remove 按 id 删除', () async {
    final s = NetworkConnectionSettings.instance;
    final a = await s.add(const NetworkConnection(
      name: 'NAS',
      protocol: NetworkProtocol.webdav,
      host: 'h',
      port: 80,
    ));
    final b = await s.add(const NetworkConnection(
      name: 'FTP',
      protocol: NetworkProtocol.ftp,
      host: 'h',
      port: 21,
    ));
    await s.remove(a.id);
    expect(s.connections.single.id, b.id);

    s.reset();
    await s.load();
    expect(s.connections.single.id, b.id);
  });

  test('byId 查找', () async {
    final s = NetworkConnectionSettings.instance;
    final a = await s.add(const NetworkConnection(
      name: 'NAS',
      protocol: NetworkProtocol.webdav,
      host: 'h',
      port: 80,
    ));
    expect(s.byId(a.id)?.name, 'NAS');
    expect(s.byId(999), isNull);
  });

  test('损坏单条 JSON 不拖垮整个列表', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('network_connections', [
      'not-json',
      '{"name":"ok","protocol":"ftp","host":"h","port":21}',
    ]);
    await NetworkConnectionSettings.instance.load();
    final s = NetworkConnectionSettings.instance;
    expect(s.connections.length, 1);
    expect(s.connections.single.name, 'ok');
  });
}