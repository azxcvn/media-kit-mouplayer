import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/bilibili/bili_credential_store.dart';

/// 内存密钥存储（测试用，替代 flutter_secure_storage 平台通道）。
class _InMemoryBiliSecureStore implements BiliSecureStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> read({required String key}) async => _map[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// 凭证解析与加密存储测试。
void main() {
  test('parse 从浏览器 Cookie 串解析', () {
    final c =
        BiliCredential.parse('SESSDATA=abc123; bili_jct=def456; DedeUserID=789');
    expect(c.sessData, 'abc123');
    expect(c.biliJct, 'def456');
    expect(c.dedeUserId, '789');
    expect(c.isValid, isTrue);
  });

  test('parse 容忍空格与多余字段', () {
    final c = BiliCredential.parse(
      'SESSDATA=abc ; bili_jct=def ; DedeUserID=789 ; sid=xyz',
    );
    expect(c.sessData, 'abc');
    expect(c.biliJct, 'def');
    expect(c.dedeUserId, '789');
  });

  test('parse 缺少 SESSDATA → 无效', () {
    final c = BiliCredential.parse('bili_jct=def456; DedeUserID=789');
    expect(c.isValid, isFalse);
  });

  test('fromCookies 从 Set-Cookie 解析', () {
    final c = BiliCredential.fromCookies({
      'SESSDATA': 'abc%2Cdef',
      'bili_jct': 'jct123',
      'DedeUserID': '789',
    });
    expect(c.sessData, 'abc%2Cdef');
    expect(c.biliJct, 'jct123');
    expect(c.dedeUserId, '789');
    expect(c.isValid, isTrue);
  });

  test('fromCookies 缺少 SESSDATA → 无效', () {
    final c = BiliCredential.fromCookies({'bili_jct': 'jct123'});
    expect(c.isValid, isFalse);
  });

  test('cookieString 拼串', () {
    const c = BiliCredential(sessData: 'a', biliJct: 'b', dedeUserId: 'c');
    expect(c.cookieString, 'SESSDATA=a; bili_jct=b; DedeUserID=c');
  });

  test('credential store 写读往返 + 清除', () async {
    final store = _InMemoryBiliSecureStore();
    final cs = BiliCredentialStore(store: store);
    await cs.write(
      const BiliCredential(sessData: 'a', biliJct: 'b', dedeUserId: 'c'),
    );
    final read = await cs.read();
    expect(read.sessData, 'a');
    expect(read.biliJct, 'b');
    expect(read.dedeUserId, 'c');
    expect(read.isValid, isTrue);

    await cs.clear();
    expect((await cs.read()).isValid, isFalse);
  });
}
