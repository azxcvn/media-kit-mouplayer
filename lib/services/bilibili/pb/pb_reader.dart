/// 轻量 protobuf wire-format 解码器（仅 varint + length-delimited 两种
/// wire type），用于解析 B 站分段弹幕接口返回的 `DmWebViewReply` /
/// `DmSegMobileReply`。思路对齐 Bilibili-Evolved 的手写解码：不为两条消息
/// 引入完整 protobuf 运行时，未知字段按 wire type 跳过（天然前向兼容）。
library;

import 'dart:convert';
import 'dart:typed_data';

/// wire type：0 = varint，2 = length-delimited（弹幕消息只用到这两种）。
const int _wtVarint = 0;
const int _wtLengthDelimited = 2;

/// 读取到的单个字段。
class PbField {
  final int fieldNumber;
  final int wireType;

  /// wireType 0（varint）时有效。
  final int varint;

  /// wireType 2（length-delimited）时有效。
  final Uint8List bytes;

  const PbField._(this.fieldNumber, this.wireType, this.varint, this.bytes);

  bool get isVarint => wireType == _wtVarint;
  bool get isLengthDelimited => wireType == _wtLengthDelimited;
}

/// 顺序读取 protobuf 字段的游标。
class PbReader {
  PbReader(Uint8List data) : _data = data;

  final Uint8List _data;
  int _pos = 0;

  bool get hasNext => _pos < _data.length;

  /// 读取下一个字段；到达末尾返回 null。
  PbField? readField() {
    if (_pos >= _data.length) return null;
    final tag = _readVarint();
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x07;
    switch (wireType) {
      case _wtVarint:
        return PbField._(fieldNumber, wireType, _readVarint(), Uint8List(0));
      case _wtLengthDelimited:
        final length = _readVarint();
        return PbField._(fieldNumber, wireType, 0, _readBytes(length));
      default:
        // 64-bit(1)/32-bit(5) 等未用到的 wire type：跳过固定字节数。
        final skip = wireType == 1 ? 8 : (wireType == 5 ? 4 : 0);
        if (skip == 0) {
          // 未知 wire type 无法安全跳过：终止解析。
          _pos = _data.length;
          return null;
        }
        if (_pos + skip > _data.length) {
          _pos = _data.length;
          return null;
        }
        _pos += skip;
        return readField();
    }
  }

  int _readVarint() {
    var result = 0;
    var shift = 0;
    // 最多读 10 字节；超出时终止（防恶意数据死循环）。
    var count = 0;
    while (_pos < _data.length && count < 10) {
      final b = _data[_pos++];
      count++;
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
    return result;
  }

  Uint8List _readBytes(int length) {
    if (length < 0) return Uint8List(0);
    final end = (_pos + length).clamp(0, _data.length);
    final sub = _data.sublist(_pos, end);
    _pos = end;
    return sub;
  }

  /// length-delimited 字段解码为 UTF-8 字符串（弹幕 content 为 UTF-8）。
  static String bytesToString(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}
