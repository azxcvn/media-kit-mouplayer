import 'package:moumou/services/device_services.dart';
import 'package:moumou/utils/natural_compare.dart';

/// 自建字幕文件选择器的排序字段（工作.md 阶段1 第 3 点）
enum SubtitleDirSort {
  name('名称'),
  size('大小'),
  date('日期');

  final String label;
  const SubtitleDirSort(this.label);
}

/// 排序目录条目（纯函数，可单测）：
/// - **目录恒排在文件之前**（两组各自独立排序，导航优先）；
/// - 目录组恒按名称自然升序；文件组按 [sort] 字段排序；
/// - [ascending] = false 时文件组降序。
List<SubtitleDirEntry> sortSubtitleDirEntries(
  Iterable<SubtitleDirEntry> entries,
  SubtitleDirSort sort, {
  bool ascending = true,
}) {
  final dirs = entries.where((e) => e.isDirectory).toList();
  final files = entries.where((e) => !e.isDirectory).toList();
  dirs.sort((a, b) => naturalCompare(a.name, b.name));
  final sign = ascending ? 1 : -1;
  files.sort((a, b) {
    final c = switch (sort) {
      SubtitleDirSort.name => naturalCompare(a.name, b.name),
      SubtitleDirSort.size => a.size.compareTo(b.size),
      SubtitleDirSort.date => a.modifiedMs.compareTo(b.modifiedMs),
    };
    return c * sign;
  });
  return [...dirs, ...files];
}
