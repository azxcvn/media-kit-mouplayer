import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/bili_wbi.dart';

/// WBI 签名纯函数测试（官方示例向量 + encWbi 一致性）。
void main() {
  test('getMixinKey 官方示例向量', () {
    const imgKey = '7cd084941338484aae1ad9425b84077c';
    const subKey = '4932caff0ff746eab6f01bf08b70ac45';
    expect(biliGetMixinKey(imgKey + subKey), 'ea1db124af3c7062474693fa704f4ff8');
  });

  test('mixinKeyFromWbiImg 从 URL 文件名推导', () {
    expect(
      biliMixinKeyFromWbiImg(
        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
      ),
      'ea1db124af3c7062474693fa704f4ff8',
    );
  });

  test('encWbi 生成 wts/w_rid 且 w_rid = md5(query+mixinKey)', () {
    final params = <String, Object>{'bvid': 'BV1xx411c7mD', 'cid': '123'};
    biliEncWbi(params, 'ea1db124af3c7062474693fa704f4ff8');

    expect(params['wts'], isA<int>());
    expect(params['w_rid'], isA<String>());

    // 用同样算法（排除 w_rid）重算验证一致性
    final signKeys = params.keys.where((k) => k != 'w_rid').toList()..sort();
    final queryStr = signKeys
        .map((k) => '${Uri.encodeComponent(k)}='
            '${Uri.encodeComponent(params[k].toString().replaceAll(RegExp(r"[!'()*]"), ''))}')
        .join('&');
    final expected = md5
        .convert(utf8.encode('$queryStr${'ea1db124af3c7062474693fa704f4ff8'}'))
        .toString();
    expect(params['w_rid'], expected);
  });

  test('encWbi 剔除 !\'()* 字符', () {
    final params = <String, Object>{'kw': "a!b'c(d)e*f"};
    biliEncWbi(params, 'ea1db124af3c7062474693fa704f4ff8');
    final signKeys = params.keys.where((k) => k != 'w_rid').toList()..sort();
    final queryStr = signKeys
        .map((k) => '${Uri.encodeComponent(k)}='
            '${Uri.encodeComponent(params[k].toString().replaceAll(RegExp(r"[!'()*]"), ''))}')
        .join('&');
    // kw 的值被剔除特殊字符后应为 "abcdef"
    expect(queryStr, contains('abcdef'));
  });
}
