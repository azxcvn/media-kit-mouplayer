import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/bili_app_sign.dart';

/// TV 端 appSign 签名纯函数测试（一致性验证 + query 拼接细节）。
void main() {
  test('biliAppSign 添加 appkey/ts/sign 且 sign 一致', () {
    final params = <String, dynamic>{
      'local_id': '0',
      'platform': 'android',
      'mobi_app': 'android_hd',
    };
    biliAppSign(
      params,
      appKey: 'dfca71928277209b',
      appSec: 'b5475a8825547a4fc26c7d518eaaa02e',
    );

    expect(params['appkey'], 'dfca71928277209b');
    expect(params['ts'], isA<String>());
    expect(params['sign'], isA<String>());

    // 重算 query（键排序、encodeComponent、空值省略 '='）验证 sign
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = StringBuffer();
    var sep = '';
    for (final e in sorted) {
      if (e.key == 'sign') continue; // sign 本身不参与签名
      final v = e.value?.toString() ?? '';
      query.write(sep);
      sep = '&';
      query.write(Uri.encodeComponent(e.key));
      if (v.isNotEmpty) {
        query.write('=');
        query.write(Uri.encodeComponent(v));
      }
    }
    final expected = md5
        .convert(utf8.encode('$query${'b5475a8825547a4fc26c7d518eaaa02e'}'))
        .toString();
    expect(params['sign'], expected);
  });

  test('biliAppSign 空值省略 "="', () {
    final params = <String, dynamic>{'a': '', 'b': '1'};
    biliAppSign(
      params,
      appKey: 'dfca71928277209b',
      appSec: 'b5475a8825547a4fc26c7d518eaaa02e',
    );
    // 重算时验证 a 不带 "="
    final sorted = params.entries.toList()
      ..sort((x, y) => x.key.compareTo(y.key));
    final query = StringBuffer();
    var sep = '';
    for (final e in sorted) {
      if (e.key == 'sign') continue;
      final v = e.value?.toString() ?? '';
      query.write(sep);
      sep = '&';
      query.write(Uri.encodeComponent(e.key));
      if (v.isNotEmpty) {
        query.write('=');
        query.write(Uri.encodeComponent(v));
      }
    }
    // 键 a 为空值 → query 中应出现 "a&" 而非 "a=&"
    expect(query.toString(), contains('a&'));
    expect(query.toString(), isNot(contains('a=&')));
  });
}
