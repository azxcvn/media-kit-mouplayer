import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕服务器设置服务测试（工作.md 第 6/7 点）：默认服务器、增删/启停、
/// 切集自动匹配开关、持久化恢复、损坏数据防御。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DanmakuServerSettings.instance.resetForTest();
  });

  final s = DanmakuServerSettings.instance;

  test('默认状态：仅默认服务器 + 自动匹配关闭', () async {
    await s.ensureLoaded();
    expect(s.servers.length, 1);
    expect(s.servers.single.isDefault, isTrue);
    expect(s.autoMatchEnabled, isFalse);
    expect(s.isDefaultEnabled, isTrue);
  });

  test('添加服务器：追加且默认启用，地址去掉末尾斜杠', () async {
    await s.addServer('我的服务器', 'https://example.com/api/');
    expect(s.servers.length, 2);
    final added = s.servers.last;
    expect(added.name, '我的服务器');
    expect(added.url, 'https://example.com/api');
    expect(added.isEnabled, isTrue);
    expect(added.isDefault, isFalse);
  });

  test('空名称/空地址不添加', () async {
    await s.addServer('  ', 'https://example.com');
    await s.addServer('名称', '  ');
    expect(s.servers.length, 1);
  });

  test('启停服务器', () async {
    await s.setServerEnabled(s.servers.single.id, false);
    expect(s.servers.single.isEnabled, isFalse);
    expect(s.isDefaultEnabled, isFalse);
    expect(s.enabledServers, isEmpty);
  });

  test('删除默认服务器被忽略；删除自建成功', () async {
    await s.addServer('自建', 'https://self.com');
    final customId = s.servers.last.id;
    await s.removeServer(s.servers.first.id); // 默认：忽略
    expect(s.servers.length, 2);
    await s.removeServer(customId);
    expect(s.servers.length, 1);
    expect(s.servers.single.isDefault, isTrue);
  });

  test('自动匹配开关持久化', () async {
    await s.setAutoMatchEnabled(true);
    expect(s.autoMatchEnabled, isTrue);
    // 模拟重启
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.autoMatchEnabled, isTrue);
  });

  test('服务器列表持久化（模拟重启 load）', () async {
    await s.addServer('自建', 'https://self.com');
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.servers.length, 2);
    expect(s.servers.last.name, '自建');
  });

  test('损坏数据：回退默认服务器且不抛异常', () async {
    SharedPreferences.setMockInitialValues({
      'dandanplay_servers': 'not-a-json{',
    });
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.servers.length, 1);
    expect(s.servers.single.isDefault, isTrue);
  });

  test('解码时兜底保留默认服务器（即使历史数据缺默认）', () async {
    SharedPreferences.setMockInitialValues({
      'dandanplay_servers': '[{"id":"c","name":"n","url":"u","isEnabled":true,"isDefault":false}]',
    });
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.servers.first.isDefault, isTrue);
    expect(s.servers.length, 2);
  });
}
