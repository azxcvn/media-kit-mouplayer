import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 哔哩哔哩登录凭证：Web 通道的 SESSDATA / bili_jct / DedeUserID（必须成对），
/// 以及 TV 通道的 access_token / refresh_token（供 tv playurl 取更高画质，阶段三用）。
///
/// 纯数据 + 解析纯函数（可单测）：响应 Set-Cookie / cookie_info.cookies、
/// 浏览器复制的 Cookie 串两种来源统一解析成 [BiliCredential]。
class BiliCredential {
  final String sessData;
  final String biliJct;
  final String dedeUserId;
  final String accessToken;
  final String refreshToken;

  const BiliCredential({
    required this.sessData,
    required this.biliJct,
    required this.dedeUserId,
    this.accessToken = '',
    this.refreshToken = '',
  });

  /// 是否具备有效登录凭证（SESSDATA 是 Web 登录态核心，非空即视为已登录候选）。
  bool get isValid => sessData.isNotEmpty;

  /// 拼成 Cookie 头字符串（用于后续 Web 请求）。
  String get cookieString =>
      'SESSDATA=$sessData; bili_jct=$biliJct; DedeUserID=$dedeUserId';

  /// 从响应 Set-Cookie 解析（登录成功时凭证在 Set-Cookie / cookie_info 下发）。
  factory BiliCredential.fromCookies(
    Map<String, String> cookies, {
    String accessToken = '',
    String refreshToken = '',
  }) {
    return BiliCredential(
      sessData: cookies['SESSDATA'] ?? '',
      biliJct: cookies['bili_jct'] ?? '',
      dedeUserId: cookies['DedeUserID'] ?? '',
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// 从浏览器复制的 Cookie 串解析（`SESSDATA=..; bili_jct=..; DedeUserID=..`）。
  factory BiliCredential.parse(String raw) {
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final k = part.substring(0, idx).trim();
      final v = part.substring(idx + 1).trim();
      if (k.isNotEmpty) map[k] = v;
    }
    return BiliCredential(
      sessData: map['SESSDATA'] ?? '',
      biliJct: map['bili_jct'] ?? '',
      dedeUserId: map['DedeUserID'] ?? '',
    );
  }
}

/// 密钥存储抽象：解耦 flutter_secure_storage，便于测试注入内存实现。
abstract class BiliSecureStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

/// 生产实现：flutter_secure_storage（Android 走 EncryptedSharedPreferences/Keystore，
/// 对齐小喵 player 的加密存储方案；凭证永不明文落盘）。
class FlutterBiliSecureStore implements BiliSecureStore {
  const FlutterBiliSecureStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// 凭证加密存储：SESSDATA / bili_jct / DedeUserID / access_token / refresh_token
/// 的读写与清除。
class BiliCredentialStore {
  BiliCredentialStore({BiliSecureStore? store})
      : _store = store ?? const FlutterBiliSecureStore();

  static const _keySessData = 'bili_sessdata';
  static const _keyBiliJct = 'bili_jct';
  static const _keyDedeUser = 'bili_dedeuserid';
  static const _keyAccessToken = 'bili_access_token';
  static const _keyRefreshToken = 'bili_refresh_token';

  final BiliSecureStore _store;

  Future<BiliCredential> read() async {
    return BiliCredential(
      sessData: await _store.read(key: _keySessData) ?? '',
      biliJct: await _store.read(key: _keyBiliJct) ?? '',
      dedeUserId: await _store.read(key: _keyDedeUser) ?? '',
      accessToken: await _store.read(key: _keyAccessToken) ?? '',
      refreshToken: await _store.read(key: _keyRefreshToken) ?? '',
    );
  }

  Future<void> write(BiliCredential credential) async {
    await _store.write(key: _keySessData, value: credential.sessData);
    await _store.write(key: _keyBiliJct, value: credential.biliJct);
    await _store.write(key: _keyDedeUser, value: credential.dedeUserId);
    await _store.write(key: _keyAccessToken, value: credential.accessToken);
    await _store.write(key: _keyRefreshToken, value: credential.refreshToken);
  }

  Future<void> clear() async {
    await _store.delete(key: _keySessData);
    await _store.delete(key: _keyBiliJct);
    await _store.delete(key: _keyDedeUser);
    await _store.delete(key: _keyAccessToken);
    await _store.delete(key: _keyRefreshToken);
  }
}
