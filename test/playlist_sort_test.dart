import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/playlist_sort.dart';
import 'package:moumou/models/video_file.dart';

VideoFile _v(String name, {DateTime? date}) => VideoFile(
      path: '/videos/$name',
      name: name,
      dateModified: date,
    );

/// 播放列表排序纯函数测试（4 种模式：名称/日期 × 升/降序）
void main() {
  final d1 = DateTime(2024, 1, 1);
  final d2 = DateTime(2024, 6, 15);
  final d3 = DateTime(2025, 3, 10);

  group('sortVideosForPlaylist', () {
    test('名称升序：自然序（2 < 12 < 112）', () {
      final videos = [
        _v('第112话.mp4'),
        _v('第12话.mp4'),
        _v('第2话.mp4'),
        _v('第1话.mp4'),
      ];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.nameAsc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['第1话.mp4', '第2话.mp4', '第12话.mp4', '第112话.mp4'],
      );
    });

    test('名称降序：自然序反转', () {
      final videos = [
        _v('第2话.mp4'),
        _v('第12话.mp4'),
        _v('第112话.mp4'),
        _v('第1话.mp4'),
      ];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.nameDesc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['第112话.mp4', '第12话.mp4', '第2话.mp4', '第1话.mp4'],
      );
    });

    test('名称大小写不敏感（A 与 a 视为同序，b 排其后）', () {
      final videos = [_v('b.mp4'), _v('A.mp4'), _v('c.mp4')];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.nameAsc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['A.mp4', 'b.mp4', 'c.mp4'],
      );
    });

    test('日期升序：按 dateModifiedMs 从旧到新', () {
      final videos = [
        _v('b.mp4', date: d3),
        _v('a.mp4', date: d1),
        _v('c.mp4', date: d2),
      ];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.dateAsc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['a.mp4', 'c.mp4', 'b.mp4'],
      );
    });

    test('日期降序：最新的在前', () {
      final videos = [
        _v('a.mp4', date: d1),
        _v('c.mp4', date: d2),
        _v('b.mp4', date: d3),
      ];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.dateDesc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['b.mp4', 'c.mp4', 'a.mp4'],
      );
    });

    test('无修改时间的视频排在末尾（升/降序一致）', () {
      final videos = [
        _v('unknown.mp4'), // 无日期
        _v('new.mp4', date: d3),
        _v('old.mp4', date: d1),
      ];
      final asc = sortVideosForPlaylist(videos, PlaylistSortMode.dateAsc);
      expect(asc.last.name, 'unknown.mp4');
      final desc = sortVideosForPlaylist(videos, PlaylistSortMode.dateDesc);
      expect(desc.last.name, 'unknown.mp4');
    });

    test('日期相同：按名称自然序稳定排序', () {
      final videos = [
        _v('第12话.mp4', date: d1),
        _v('第2话.mp4', date: d1),
        _v('第112话.mp4', date: d1),
      ];
      final sorted =
          sortVideosForPlaylist(videos, PlaylistSortMode.dateAsc);
      expect(
        sorted.map((v) => v.name).toList(),
        ['第2话.mp4', '第12话.mp4', '第112话.mp4'],
      );
    });

    test('纯函数：不修改入参列表', () {
      final videos = [
        _v('b.mp4', date: d3),
        _v('a.mp4', date: d1),
      ];
      final original = [...videos];
      sortVideosForPlaylist(videos, PlaylistSortMode.nameAsc);
      sortVideosForPlaylist(videos, PlaylistSortMode.dateDesc);
      expect(videos, original);
    });

    test('空列表与单元素', () {
      expect(
        sortVideosForPlaylist(const [], PlaylistSortMode.nameAsc),
        isEmpty,
      );
      final one = [_v('only.mp4')];
      expect(sortVideosForPlaylist(one, PlaylistSortMode.nameDesc), one);
    });
  });

  group('folderOfPath / filterVideosInFolder', () {
    test('提取文件夹路径：最后一个 / 之前的片段', () {
      expect(
        folderOfPath('/storage/emulated/0/DCIM/xxx.mp4'),
        '/storage/emulated/0/DCIM',
      );
      expect(folderOfPath('/a/b.mp4'), '/a');
      expect(folderOfPath('/root.mp4'), '');
      expect(folderOfPath(''), '');
    });

    test('过滤同目录视频', () {
      final videos = [
        VideoFile(path: '/videos/s01/e01.mp4', name: 'e01.mp4'),
        VideoFile(path: '/videos/s01/e02.mp4', name: 'e02.mp4'),
        VideoFile(path: '/videos/s02/e01.mp4', name: 's2e01.mp4'),
        VideoFile(path: '/other/movie.mp4', name: 'movie.mp4'),
      ];
      final filtered =
          filterVideosInFolder(videos, '/videos/s01');
      expect(
        filtered.map((v) => v.name).toList(),
        ['e01.mp4', 'e02.mp4'],
      );
      // 纯函数：不改动入参
      expect(videos.length, 4);
    });

    test('排序后当前项索引可定位（配合面板滚动）', () {
      final videos = [
        _v('第3话.mp4'),
        _v('第1话.mp4'),
        _v('第2话.mp4'),
      ];
      const current = '第3话.mp4';
      // 名称升序后，当前项在最后 → 索引 2
      final asc = sortVideosForPlaylist(videos, PlaylistSortMode.nameAsc);
      expect(asc.indexWhere((v) => v.name == current), 2);
      // 名称降序后，当前项在开头 → 索引 0
      final desc = sortVideosForPlaylist(videos, PlaylistSortMode.nameDesc);
      expect(desc.indexWhere((v) => v.name == current), 0);
    });
  });
}
