import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/danmaku_server.dart';

/// 弹幕服务器模型测试（默认服务器 + JSON 序列化 + copyWith）。
void main() {
  test('默认服务器：官方地址 + 启用 + 不可删除', () {
    final s = DanmakuServer.createDefault();
    expect(s.id, DanmakuServer.defaultId);
    expect(s.name, DanmakuServer.defaultName);
    expect(s.url, DanmakuServer.defaultUrl);
    expect(s.isEnabled, isTrue);
    expect(s.isDefault, isTrue);
  });

  test('toJson/fromJson 往返', () {
    const s = DanmakuServer(
      id: 'custom-1',
      name: '我的服务器',
      url: 'https://example.com/api',
      isEnabled: false,
      isDefault: false,
    );
    final restored = DanmakuServer.fromJson(s.toJson());
    expect(restored, isNotNull);
    expect(restored!.id, 'custom-1');
    expect(restored.name, '我的服务器');
    expect(restored.url, 'https://example.com/api');
    expect(restored.isEnabled, isFalse);
    expect(restored.isDefault, isFalse);
  });

  test('fromJson 缺字段回退默认（启用 true / 非默认）', () {
    final s = DanmakuServer.fromJson({'id': 'a', 'name': 'n', 'url': 'u'});
    expect(s, isNotNull);
    expect(s!.isEnabled, isTrue);
    expect(s.isDefault, isFalse);
  });

  test('fromJson 字段类型不符 → null', () {
    expect(DanmakuServer.fromJson({'id': 1, 'name': 'n', 'url': 'u'}), isNull);
    expect(DanmakuServer.fromJson({'id': 'a', 'name': 'n'}), isNull);
  });

  test('copyWith 只改指定字段，id/isDefault 不变', () {
    const s = DanmakuServer(
      id: 'default',
      name: '弹弹Play（默认）',
      url: 'https://api.dandanplay.net',
      isEnabled: true,
      isDefault: true,
    );
    final toggled = s.copyWith(isEnabled: false);
    expect(toggled.id, s.id);
    expect(toggled.isDefault, isTrue);
    expect(toggled.isEnabled, isFalse);
    expect(toggled.name, s.name);
  });
}
