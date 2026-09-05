/// 哔哩哔哩反爬设备指纹纯函数（完整版，对齐 Bili23-Downloader / PiliPlus）：
///
/// - [_murmur3x64_128]：buvid_fp 的 murmur3_x64_128 哈希（种子 31，输入 = UA）；
/// - [genBiliUuid] / [genBLsid] / [genBuvidFp]：本地生成 `_uuid` / `b_lsid` / `buvid_fp`；
/// - [biliTicketHexsign]：GenWebTicket 的 HMAC-SHA256 hexsign；
/// - [genExClimbWuzhiPayload]：激活 buvid3 的 ExClimbWuzhi 请求 payload（对齐 PiliPlus 精简版）；
/// - [randomDmImgStr] / [genDmImgParams]：playurl 的 `dm_img_*` 反爬参数。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final Random _rng = Random();

/// murmur3_x64_128（返回 128 位值，低 64 位 = h1、高 64 位 = h2）。
/// 移植自 Bili23 `cookie.py get_buvid_fp`（其又来自 murmur3 参考实现）。
BigInt murmur3x64_128(List<int> src, int seed) {
  final c1 = BigInt.parse('87c37b91114253d5', radix: 16);
  final c2 = BigInt.parse('4cf5ad432745937f', radix: 16);
  final c3 = BigInt.parse('52dce729', radix: 16);
  final c4 = BigInt.parse('38495ab5', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  const r1 = 27, r2 = 31, r3 = 33;

  BigInt rotl(BigInt x, int k) => ((x << k) | (x >> (64 - k))) & mask;

  BigInt fmix64(BigInt k) {
    k ^= k >> 33;
    k = (k * BigInt.parse('ff51afd7ed558ccd', radix: 16)) & mask;
    k ^= k >> 33;
    k = (k * BigInt.parse('c4ceb9fe1a85ec53', radix: 16)) & mask;
    k ^= k >> 33;
    return k;
  }

  BigInt leU64(int off) {
    var v = BigInt.zero;
    for (var k = 7; k >= 0; k--) {
      v = (v << 8) | BigInt.from(src[off + k]);
    }
    return v;
  }

  var h1 = BigInt.from(seed);
  var h2 = BigInt.from(seed);
  var i = 0;
  var processed = 0;
  while (true) {
    final remaining = src.length - i;
    if (remaining >= 16) {
      var k1 = leU64(i);
      var k2 = leU64(i + 8);
      k1 = rotl((k1 * c1) & mask, r2);
      k1 = (k1 * c2) & mask;
      h1 ^= k1;
      h1 = ((rotl(h1, r1) + h2) * BigInt.from(5) + c3) & mask;
      k2 = rotl((k2 * c2) & mask, r3);
      k2 = (k2 * c1) & mask;
      h2 ^= k2;
      h2 = ((rotl(h2, r2) + h1) * BigInt.from(5) + c4) & mask;
      i += 16;
      processed += 16;
    } else if (remaining == 0) {
      h1 ^= BigInt.from(processed);
      h2 ^= BigInt.from(processed);
      h1 = (h1 + h2) & mask;
      h2 = (h2 + h1) & mask;
      h1 = fmix64(h1);
      h2 = fmix64(h2);
      h1 = (h1 + h2) & mask;
      h2 = (h2 + h1) & mask;
      return (h2 << 64) | h1;
    } else {
      var k1 = BigInt.zero;
      var k2 = BigInt.zero;
      final len = remaining;
      if (len >= 15) k2 ^= BigInt.from(src[i + 14]) << 48;
      if (len >= 14) k2 ^= BigInt.from(src[i + 13]) << 40;
      if (len >= 13) k2 ^= BigInt.from(src[i + 12]) << 32;
      if (len >= 12) k2 ^= BigInt.from(src[i + 11]) << 24;
      if (len >= 11) k2 ^= BigInt.from(src[i + 10]) << 16;
      if (len >= 10) k2 ^= BigInt.from(src[i + 9]) << 8;
      if (len >= 9) {
        k2 ^= BigInt.from(src[i + 8]);
        k2 = rotl((k2 * c2) & mask, r3);
        k2 = (k2 * c1) & mask;
        h2 ^= k2;
      }
      if (len >= 8) k1 ^= BigInt.from(src[i + 7]) << 56;
      if (len >= 7) k1 ^= BigInt.from(src[i + 6]) << 48;
      if (len >= 6) k1 ^= BigInt.from(src[i + 5]) << 40;
      if (len >= 5) k1 ^= BigInt.from(src[i + 4]) << 32;
      if (len >= 4) k1 ^= BigInt.from(src[i + 3]) << 24;
      if (len >= 3) k1 ^= BigInt.from(src[i + 2]) << 16;
      if (len >= 2) k1 ^= BigInt.from(src[i + 1]) << 8;
      if (len >= 1) {
        k1 ^= BigInt.from(src[i]);
        k1 = rotl((k1 * c1) & mask, r2);
        k1 = (k1 * c2) & mask;
        h1 ^= k1;
      }
      i += len;
      processed += len;
    }
  }
}

/// 生成 `buvid_fp`：murmur3_x64_128(UA, 31) 的 32 位十六进制（低 64 位在前、高 64 位在后）。
String genBuvidFp(String userAgent) {
  final m = murmur3x64_128(utf8.encode(userAgent), 31);
  final mask = (BigInt.one << 64) - BigInt.one;
  final low = (m & mask).toRadixString(16).padLeft(16, '0');
  final high = (m >> 64).toRadixString(16).padLeft(16, '0');
  return '$low$high';
}

/// 生成 `_uuid`（Bili23 格式：8-4-4-4-12 + 5 位时间戳 + "infoc"）。
String genBiliUuid() {
  const hex = '123456789ABCDEF';
  String part(int n) => List.generate(n, (_) => hex[_rng.nextInt(hex.length)]).join();
  final t = (DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
  return '${part(8)}-${part(4)}-${part(4)}-${part(4)}-${part(12)}$t'
      'infoc';
}

/// 生成 `b_lsid`：8 位大写十六进制随机 + "_" + 时间戳十六进制（对齐 Bili23）。
String genBLsid() {
  String randHex() => List.generate(
        8,
        (_) => _rng.nextInt(16).toRadixString(16).toUpperCase(),
      ).join();
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase();
  return '${randHex()}_$ts';
}

/// GenWebTicket 的 hexsign：HMAC-SHA256(key="XgwSnGZ1p", message="ts{时间戳}") 的十六进制。
String biliTicketHexsign(int timestamp) =>
    Hmac(sha256, utf8.encode('XgwSnGZ1p'))
        .convert(utf8.encode('ts$timestamp'))
        .toString();

/// 生成 ExClimbWuzhi（激活 buvid3）请求体（对齐 PiliPlus 精简 payload）。
String genExClimbWuzhiPayload() {
  final bytes = <int>[
    ...List.generate(32, (_) => _rng.nextInt(256)),
    0, 0, 0, 0, 73, 69, 78, 68, // PNG IEND
    ...List.generate(4, (_) => _rng.nextInt(256)),
  ];
  final b64 = base64.encode(bytes);
  final randPngEnd = b64.substring(b64.length - 50);
  final inner = jsonEncode({
    '3064': 1,
    '39c8': '333.1387.fp.risk',
    '3c43': {'adca': 'Linux', 'bfe9': randPngEnd},
  });
  return jsonEncode({'payload': inner});
}

/// 生成 `dm_img_str` 等随机 base64 串（字节取值避开 `%`，对齐 PiliPlus）。
String randomDmImgStr(int minLength, int maxLength) {
  final n = minLength + _rng.nextInt(maxLength - minLength + 1);
  final bytes = List.generate(n, (_) => 0x26 + _rng.nextInt(0x59));
  final b64 = base64.encode(bytes);
  return b64.substring(0, b64.length - 2);
}

/// 生成 playurl 的 `dm_img_*` 反爬参数（每次请求随机，对齐 PiliPlus）。
Map<String, String> genDmImgParams() => {
      'dm_img_list': '[]',
      'dm_img_str': randomDmImgStr(16, 64),
      'dm_cover_img_str': randomDmImgStr(32, 128),
      'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
    };
