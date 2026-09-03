/// protobuf wire-format 编码辅助（仅测试用，用于构造弹幕接口的 mock 响应）。
library;

import 'dart:convert';
import 'dart:typed_data';

List<int> pbVarint(int value) {
  var v = value;
  final out = <int>[];
  do {
    final b = v & 0x7F;
    v >>= 7;
    out.add(v == 0 ? b : b | 0x80);
  } while (v != 0);
  return out;
}

Uint8List pbFieldVarint(int number, int value) =>
    Uint8List.fromList([...pbVarint(number << 3), ...pbVarint(value)]);

Uint8List pbFieldBytes(int number, List<int> payload) =>
    Uint8List.fromList([
      ...pbVarint((number << 3) | 2),
      ...pbVarint(payload.length),
      ...payload,
    ]);

Uint8List pbConcat(List<List<int>> parts) {
  final all = <int>[];
  for (final p in parts) {
    all.addAll(p);
  }
  return Uint8List.fromList(all);
}

/// `DanmakuElem`（字段 1=id、2=progress(ms)、3=mode、5=color、7=content）。
Uint8List encodeDanmakuElem({
  int id = 1,
  int progressMs = 1000,
  int mode = 1,
  int color = 0xFFFFFF,
  String content = 'hello',
}) {
  return pbConcat([
    pbFieldVarint(1, id),
    pbFieldVarint(2, progressMs),
    pbFieldVarint(3, mode),
    pbFieldVarint(5, color),
    pbFieldBytes(7, utf8.encode(content)),
  ]);
}

/// `DmSegMobileReply`（字段 1=elems repeated、字段 2=state）。
Uint8List encodeSegMobileReply(List<Uint8List> elems, {int state = 0}) {
  final parts = <List<int>>[];
  if (state != 0) parts.add(pbFieldVarint(2, state));
  for (final e in elems) {
    parts.add(pbFieldBytes(1, e));
  }
  return pbConcat(parts);
}

/// `DmWebViewReply`（字段 4=dmSge → DmSegConfig 字段 2=total）。
Uint8List encodeWebViewReply(int totalSegments) {
  final segConfig = pbConcat([pbFieldVarint(2, totalSegments)]);
  return pbConcat([pbFieldBytes(4, segConfig)]);
}
