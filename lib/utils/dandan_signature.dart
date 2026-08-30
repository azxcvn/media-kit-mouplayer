/// 弹弹Play 开放弹幕网络签名纯函数（签名验证模式）：
/// `base64(sha256(AppId + Timestamp + Path + AppSecret))`。
///
/// 纯函数（无状态、无 Flutter 依赖），供 `services/dandan_play_api.dart`
/// 生成请求头 `X-Signature`，可单测。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 计算签名（签名验证模式，对齐官方算法）。
///
/// [appId] 应用 ID；[timestamp] Unix 秒级时间戳（字符串形式拼接）；
/// [path] API 路径（以 `/` 开头、小写、不含域名与查询参数）；
/// [appSecret] 应用密钥。
String dandanSignature({
  required String appId,
  required int timestamp,
  required String path,
  required String appSecret,
}) {
  final data = '$appId$timestamp$path$appSecret';
  final digest = sha256.convert(utf8.encode(data)).bytes;
  return base64Encode(digest);
}
