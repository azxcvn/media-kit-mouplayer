import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/http_byte_range.dart';

void main() {
  test('bytes=start-end 基本解析', () {
    final r = HttpByteRange.parse('bytes=0-499', 1000);
    expect(r!.start, 0);
    expect(r.endInclusive, 499);
    expect(r.length, 500);
  });

  test('bytes=start- 到末尾', () {
    final r = HttpByteRange.parse('bytes=500-', 1000);
    expect(r!.start, 500);
    expect(r.endInclusive, 999);
    expect(r.length, 500);
  });

  test('bytes=-suffix 请求末尾 N 字节', () {
    final r = HttpByteRange.parse('bytes=-500', 1000);
    expect(r!.start, 500);
    expect(r.endInclusive, 999);
    expect(r.length, 500);
  });

  test('suffix 超过总长时收敛到整个文件', () {
    final r = HttpByteRange.parse('bytes=-2000', 1000);
    expect(r!.start, 0);
    expect(r.endInclusive, 999);
  });

  test('越界 end 收敛到末尾', () {
    final r = HttpByteRange.parse('bytes=0-99999', 1000);
    expect(r!.start, 0);
    expect(r.endInclusive, 999);
  });

  test('大小写不敏感', () {
    final r = HttpByteRange.parse('BYTES=0-9', 100);
    expect(r!.start, 0);
    expect(r.endInclusive, 9);
  });

  test('非法/不可满足返回 null', () {
    expect(HttpByteRange.parse('bytes=-', 100), isNull);
    expect(HttpByteRange.parse('bytes=0-0-0', 100), isNull);
    expect(HttpByteRange.parse('bytes=100-', 100), isNull); // start 越界
    expect(HttpByteRange.parse('bytes=5-2', 100), isNull); // end < start
    expect(HttpByteRange.parse('', 100), isNull);
    expect(HttpByteRange.parse('bytes=0-9', 0), isNull); // 总长为 0
    expect(HttpByteRange.parse('bytes=0-9', -1), isNull);
  });
}