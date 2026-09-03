import 'dart:convert';

import 'package:crypto/crypto.dart';

/// WBI 签名纯函数（算法见
/// https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md）。
///
/// - [biliGetMixinKey]：把 nav 接口返回的 img_key + sub_key 按混淆表重排取前 32 位；
/// - [biliEncWbi]：为请求参数加 `wts` + `w_rid`（MD5(query + mixinKey)）。
///
/// 无状态、可单测；移植自 PiliPlus `utils/wbi_sign.dart`，混淆表以
/// bilibili-API-collect / Bili23 的 64 项表为准（PiliPlus 只保留了前 32 项，
/// 结果等价）。

final RegExp _chrFilter = RegExp(r"[!'()*]");

/// 固定混淆表（64 项，与服务端一并可能变更，变更时签名会集体失败）。
const List<int> kBiliMixinKeyEncTab = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];

/// 从 `img_key + sub_key`（共 64 字符）推导 WBI 混淆密钥（取前 32 位）。
String biliGetMixinKey(String orig) {
  final codeUnits = orig.codeUnits;
  final sb = StringBuffer();
  for (final i in kBiliMixinKeyEncTab) {
    if (i < codeUnits.length) sb.writeCharCode(codeUnits[i]);
  }
  return sb.toString().substring(0, 32);
}

/// 从 nav 接口的 wbi_img 两个 URL 推导 mixinKey（URL 文件名去扩展名拼接）。
String biliMixinKeyFromWbiImg(String imgUrl, String subUrl) {
  String fileName(String url) {
    final base = url.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot >= 0 ? base.substring(0, dot) : base;
  }

  return biliGetMixinKey(fileName(imgUrl) + fileName(subUrl));
}

/// 为请求参数就地追加 `wts` 与 `w_rid`（WBI 签名）。参数会被就地修改。
void biliEncWbi(Map<String, Object> params, String mixinKey) {
  params['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final keys = params.keys.toList()..sort();
  final queryStr = keys
      .map((k) => '${Uri.encodeComponent(k)}='
          '${Uri.encodeComponent(params[k].toString().replaceAll(_chrFilter, ''))}')
      .join('&');
  params['w_rid'] = md5.convert(utf8.encode(queryStr + mixinKey)).toString();
}
