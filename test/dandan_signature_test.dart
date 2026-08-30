import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/dandan_signature.dart';

/// 弹弹Play 签名纯函数测试：官方示例 + 合成密钥的已知向量（SHA256/Base64）。
///
/// ⚠️ **禁止在本文件里写入真实 AppId / AppSecret**（工作.md 第 3 点）：
/// 真实密钥只存 gitignored 的 `lib/services/dandan_play_keys.dart`。签名是
/// 纯函数，用下面的合成凭据（[_testAppId] / [_testAppSecret]）即可完整覆盖
/// 算法正确性；官方文档示例向量另外锁死字节序与 Base64 编码。
void main() {
  test('官方示例向量：base64(sha256(AppId+Timestamp+Path+AppSecret))', () {
    final sig = dandanSignature(
      appId: 'your_app_id',
      timestamp: 1735660800,
      path: '/api/v2/comment/123450001',
      appSecret: 'your_app_secret',
    );
    expect(sig, 'MNBT8iOsIplI/GSkJEAH3V1AlpTyH1aMPJ1nedenEsw=');
  });

  test('三个真实调用路径的已知向量（合成密钥）', () {
    // search/episodes / comment/{id} / match —— 覆盖 API 客户端实际签名的
    // 三条路径，锁死 path 参与拼接的位置与形态
    expect(
      dandanSignature(
        appId: _testAppId,
        timestamp: _testTimestamp,
        path: '/api/v2/search/episodes',
        appSecret: _testAppSecret,
      ),
      'qNPuymcnoCpy7K9AsFjILG2p+dxSixlmDT4Y7hg1l/I=',
    );
    expect(
      dandanSignature(
        appId: _testAppId,
        timestamp: _testTimestamp,
        path: '/api/v2/comment/42',
        appSecret: _testAppSecret,
      ),
      'OBAZpLJwQ+ODPcCcrQ3g88BfSZkxsGHdtFvgaXzO4Us=',
    );
    expect(
      dandanSignature(
        appId: _testAppId,
        timestamp: _testTimestamp,
        path: '/api/v2/match',
        appSecret: _testAppSecret,
      ),
      '4UhY1KNiHQ8zvn/SnjszHLVzMAUurXdJ/XxFwFuKBIM=',
    );
  });

  test('任何输入变化都会改变签名（时间戳/路径/密钥）', () {
    final base = dandanSignature(
      appId: 'a',
      timestamp: 100,
      path: '/p',
      appSecret: 's',
    );
    expect(
      dandanSignature(appId: 'a', timestamp: 101, path: '/p', appSecret: 's'),
      isNot(base),
    );
    expect(
      dandanSignature(appId: 'a', timestamp: 100, path: '/q', appSecret: 's'),
      isNot(base),
    );
    expect(
      dandanSignature(appId: 'a', timestamp: 100, path: '/p', appSecret: 't'),
      isNot(base),
    );
    expect(
      dandanSignature(appId: 'b', timestamp: 100, path: '/p', appSecret: 's'),
      isNot(base),
    );
  });

  test('输出为标准 Base64（44 字符 + = 填充，对应 32 字节 SHA256）', () {
    final sig = dandanSignature(
      appId: 'a',
      timestamp: 1,
      path: '/p',
      appSecret: 's',
    );
    expect(sig.length, 44);
    expect(sig.endsWith('='), isTrue);
  });
}

/// 合成测试凭据（**非真实密钥**，真实值见 gitignored 的 dandan_play_keys.dart）
const String _testAppId = 'testappid';
const String _testAppSecret = 'testappsecret';
const int _testTimestamp = 1735660800;
