import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_server.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕服务器设置服务测试（工作.md 第 6/7 点）：默认服务器、增删/启停、
/// 切集自动匹配开关、**与默认弹弹Play 服务器的互斥限制**、持久化恢复、
/// 损坏数据防御。
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

  test('自动匹配开关持久化（默认服务器已停用，开关可生效）', () async {
    await s.setServerEnabled(DanmakuServer.defaultId, false);
    expect(await s.setAutoMatchEnabled(true), isTrue);
    expect(s.autoMatchEnabled, isTrue);
    // 模拟重启
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.autoMatchPreference, isTrue);
  });

  // ── 与默认弹弹Play 服务器互斥（工作.md 第 7 点，收尾恢复的限制）──

  test('默认服务器启用时：不允许开启，setter 返回 false 且不写偏好', () async {
    await s.ensureLoaded();
    expect(s.isDefaultEnabled, isTrue);
    expect(s.autoMatchAllowed, isFalse);
    // 副标题用短指引；toast 用含服务器名的完整说明
    expect(s.autoMatchBlockedReason, '请先停用弹弹Play 服务器');
    expect(s.autoMatchBlockedMessage, contains(DanmakuServer.defaultName));
    expect(s.autoMatchBlockedMessage, contains('切集自动匹配弹幕'));

    expect(await s.setAutoMatchEnabled(true), isFalse);
    expect(s.autoMatchPreference, isFalse);
    expect(s.autoMatchEnabled, isFalse);
  });

  test('默认服务器启用时：既有偏好被压制为不生效，但偏好本身保留', () async {
    await s.setServerEnabled(DanmakuServer.defaultId, false);
    await s.setAutoMatchEnabled(true);
    expect(s.autoMatchEnabled, isTrue);

    // 重新启用默认服务器 → 立即失效（运行时判定与 UI 同一个 getter）
    await s.setServerEnabled(DanmakuServer.defaultId, true);
    expect(s.autoMatchEnabled, isFalse);
    expect(s.autoMatchPreference, isTrue, reason: '偏好不被静默丢弃');
    expect(s.autoMatchAllowed, isFalse);

    // 再次停用默认服务器 → 用户此前的选择自动恢复
    await s.setServerEnabled(DanmakuServer.defaultId, false);
    expect(s.autoMatchEnabled, isTrue);
    expect(s.autoMatchBlockedReason, isNull);
    expect(s.autoMatchBlockedMessage, isNull);
  });

  test('默认服务器启用时：关闭动作永远允许', () async {
    await s.setServerEnabled(DanmakuServer.defaultId, false);
    await s.setAutoMatchEnabled(true);
    await s.setServerEnabled(DanmakuServer.defaultId, true);
    expect(await s.setAutoMatchEnabled(false), isTrue);
    expect(s.autoMatchPreference, isFalse);
  });

  test('自建服务器启用不影响限制（只与默认服务器互斥）', () async {
    await s.setServerEnabled(DanmakuServer.defaultId, false);
    await s.addServer('自建', 'https://self.com');
    expect(s.autoMatchAllowed, isTrue);
    expect(await s.setAutoMatchEnabled(true), isTrue);
    expect(s.autoMatchEnabled, isTrue);
  });

  test('持久化偏好为 true 但默认服务器启用时：重启后不生效', () async {
    SharedPreferences.setMockInitialValues({
      'danmaku_auto_match_enabled': true,
    });
    DanmakuServerSettings.instance.resetForTest();
    await s.ensureLoaded();
    expect(s.autoMatchPreference, isTrue);
    expect(s.autoMatchEnabled, isFalse, reason: '默认服务器启用 → 恒不生效');
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
