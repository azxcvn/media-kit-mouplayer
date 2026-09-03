import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/bilibili/pb/pb_reader.dart';

import 'pb_test_helper.dart';

void main() {
  group('PbReader', () {
    test('读取 varint 字段', () {
      final data = pbConcat([pbFieldVarint(1, 150)]);
      final reader = PbReader(data);
      final f = reader.readField();
      expect(f, isNotNull);
      expect(f!.fieldNumber, 1);
      expect(f.isVarint, isTrue);
      expect(f.varint, 150);
      expect(reader.hasNext, isFalse);
    });

    test('读取 length-delimited 字段并解 UTF-8', () {
      final payload = [104, 105]; // "hi"
      final data = pbConcat([pbFieldBytes(7, payload)]);
      final f = PbReader(data).readField();
      expect(f!.isLengthDelimited, isTrue);
      expect(PbReader.bytesToString(f.bytes), 'hi');
    });

    test('多字段顺序读取', () {
      final data = pbConcat([
        pbFieldVarint(2, 5),
        pbFieldBytes(1, [1, 2, 3]),
        pbFieldVarint(3, 99),
      ]);
      final reader = PbReader(data);
      final f1 = reader.readField()!;
      final f2 = reader.readField()!;
      final f3 = reader.readField()!;
      expect(f1.fieldNumber, 2);
      expect(f1.varint, 5);
      expect(f2.fieldNumber, 1);
      expect(f2.bytes, [1, 2, 3]);
      expect(f3.fieldNumber, 3);
      expect(f3.varint, 99);
      expect(reader.hasNext, isFalse);
    });

    test('跳过未知 wire type（64-bit/32-bit）', () {
      // 字段 1 是 64-bit（wire type 1）：tag + 8 字节
      final data = Uint8List.fromList([
        1 << 3 | 1, // field 1, wire type 1
        0, 0, 0, 0, 0, 0, 0, 0,
        ...pbVarint(2 << 3), // field 2, wire type 0
        ...pbVarint(42),
      ]);
      final reader = PbReader(data);
      final f = reader.readField();
      expect(f!.fieldNumber, 2);
      expect(f.varint, 42);
    });

    test('空数据返回 null', () {
      expect(PbReader(Uint8List(0)).readField(), isNull);
    });
  });

  group('弹幕消息解析（字段号对齐 PiliPlus v1.pb.dart）', () {
    test('DmWebViewReply → dmSge.total', () {
      final data = encodeWebViewReply(12);
      // 手动解析：字段 4（dmSge）→ 字段 2（total）
      final reader = PbReader(data);
      var total = 0;
      while (reader.hasNext) {
        final f = reader.readField();
        if (f == null) break;
        if (f.fieldNumber == 4 && f.isLengthDelimited) {
          final cfg = PbReader(f.bytes);
          while (cfg.hasNext) {
            final cf = cfg.readField();
            if (cf == null) break;
            if (cf.fieldNumber == 2 && cf.isVarint) total = cf.varint;
          }
        }
      }
      expect(total, 12);
    });

    test('DanmakuElem 字段解析', () {
      final elem = encodeDanmakuElem(
        id: 123,
        progressMs: 5432,
        mode: 4,
        color: 0x00FF00,
        content: '测试弹幕',
      );
      final reader = PbReader(elem);
      var id = 0, progressMs = 0, mode = 0, color = 0;
      String content = '';
      while (reader.hasNext) {
        final f = reader.readField();
        if (f == null) break;
        if (f.fieldNumber == 1 && f.isVarint) {
          id = f.varint;
        } else if (f.fieldNumber == 2 && f.isVarint) {
          progressMs = f.varint;
        } else if (f.fieldNumber == 3 && f.isVarint) {
          mode = f.varint;
        } else if (f.fieldNumber == 5 && f.isVarint) {
          color = f.varint;
        } else if (f.fieldNumber == 7 && f.isLengthDelimited) {
          content = PbReader.bytesToString(f.bytes);
        }
      }
      expect(id, 123);
      expect(progressMs, 5432);
      expect(mode, 4);
      expect(color, 0x00FF00);
      expect(content, '测试弹幕');
    });
  });
}
