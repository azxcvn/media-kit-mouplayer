import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/utils/subtitle_sort.dart';

void main() {
  SubtitleDirEntry dir(String name) => SubtitleDirEntry(
        name: name,
        path: '/root/$name',
        isDirectory: true,
        size: 0,
        modifiedMs: 0,
      );

  SubtitleDirEntry file(String name, {int size = 0, int modifiedMs = 0}) =>
      SubtitleDirEntry(
        name: name,
        path: '/root/$name',
        isDirectory: false,
        size: size,
        modifiedMs: modifiedMs,
      );

  group('sortSubtitleDirEntries（工作.md 阶段1 第 3 点自建选择器排序）', () {
    test('目录恒排在文件之前，目录内按名称升序', () {
      final sorted = sortSubtitleDirEntries(
        [file('b.srt'), dir('zeta'), dir('alpha'), file('a.srt')],
        SubtitleDirSort.name,
      );
      expect(sorted.map((e) => e.name).toList(), [
        'alpha',
        'zeta',
        'a.srt',
        'b.srt',
      ]);
    });

    test('按大小排序（升/降序）', () {
      final sorted = sortSubtitleDirEntries(
        [file('big.srt', size: 300), file('small.srt', size: 10), file('mid.srt', size: 100)],
        SubtitleDirSort.size,
      );
      expect(sorted.map((e) => e.name).toList(), [
        'small.srt',
        'mid.srt',
        'big.srt',
      ]);
      final desc = sortSubtitleDirEntries(
        [file('big.srt', size: 300), file('small.srt', size: 10), file('mid.srt', size: 100)],
        SubtitleDirSort.size,
        ascending: false,
      );
      expect(desc.map((e) => e.name).toList(), [
        'big.srt',
        'mid.srt',
        'small.srt',
      ]);
    });

    test('按日期排序', () {
      final sorted = sortSubtitleDirEntries(
        [
          file('old.srt', modifiedMs: 100),
          file('new.srt', modifiedMs: 300),
          file('mid.srt', modifiedMs: 200),
        ],
        SubtitleDirSort.date,
      );
      expect(sorted.map((e) => e.name).toList(), [
        'old.srt',
        'mid.srt',
        'new.srt',
      ]);
    });

    test('空列表原样返回', () {
      expect(sortSubtitleDirEntries(const [], SubtitleDirSort.name), isEmpty);
    });
  });
}
