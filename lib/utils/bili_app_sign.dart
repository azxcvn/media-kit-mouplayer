import 'dart:convert';

import 'package:crypto/crypto.dart';

/// TV 端 appSign 签名纯函数（移植自 PiliPlus `utils/app_sign.dart`）。
///
/// 就地给参数加 `appkey` + `ts` + `sign`；`sign = md5(键排序后的 query + appsec)`。
/// 供 TV 通道扫码登录（阶段一）与 `tv playurl`（阶段三）用。
///
/// query 拼接细节对齐 PiliPlus：`Uri.encodeComponent(key)` 恒写，值为空时省略
/// `=`；值非空时 `=encodeComponent(value)`；键值对按 key 字典序。
void biliAppSign(
  Map<String, dynamic> params, {
  required String appKey,
  required String appSec,
}) {
  params['appkey'] = appKey;
  params['ts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final sorted = params.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final query = StringBuffer();
  var separator = '';
  for (final entry in sorted) {
    final value = entry.value?.toString() ?? '';
    query.write(separator);
    separator = '&';
    query.write(Uri.encodeComponent(entry.key));
    if (value.isNotEmpty) {
      query.write('=');
      query.write(Uri.encodeComponent(value));
    }
  }
  params['sign'] = md5.convert(utf8.encode(query.toString() + appSec)).toString();
}
