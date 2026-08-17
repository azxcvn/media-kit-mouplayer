import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ViewSettings.sortTree / sortFolders / sortVideos 排序逻辑测试
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TreeNode folder(
    String name, {
    int count = 0,
    int size = 0,
    DateTime? date,
    List<TreeNode> children = const [],
  }) {
    return TreeNode(
      name: name,
      path: '/$name',
      type: TreeNodeType.folder,
      videoCount: count,
      totalSize: size,
      dateModified: date,
      children: children,
    );
  }

  TreeNode video(
    String name, {
    int size = 0,
    int duration = 0,
    DateTime? date,
  }) {
    return TreeNode(
      name: name,
      path: '/$name.mp4',
      type: TreeNodeType.video,
      video: VideoFile(
        path: '/$name.mp4',
        name: name,
        size: size,
        durationMs: duration,
        dateModified: date,
      ),
    );
  }

  group('sortTree', () {
    test('文件夹在前、视频在后', () {
      final settings = ViewSettings();
      final result = settings.sortTree([video('b'), folder('a'), video('a')]);
      expect(result.length, 3);
      expect(result[0].isFolder, isTrue);
      expect(result[1].isFolder, isFalse);
      expect(result[2].isFolder, isFalse);
      // 文件夹名 a 在最前，视频 a/b 在后
      expect(result.map((n) => n.name).toList(), ['a', 'a', 'b']);
    });

    test('文件夹按名称升序', () async {
      final settings = ViewSettings();
      await settings.setSortField(SortField.name);
      final result = settings.sortTree([folder('b'), folder('a')]);
      expect(result.map((n) => n.name).toList(), ['a', 'b']);
    });

    test('文件夹按数量降序', () async {
      final settings = ViewSettings();
      await settings.setSortField(SortField.count);
      await settings.setSortOrder(SortOrder.desc);
      final result = settings.sortTree([
        folder('few', count: 1),
        folder('many', count: 5),
      ]);
      expect(result.map((n) => n.name).toList(), ['many', 'few']);
    });

    test('文件夹按大小升序', () async {
      final settings = ViewSettings();
      await settings.setSortField(SortField.size);
      final result = settings.sortTree([
        folder('big', size: 100),
        folder('small', size: 10),
      ]);
      expect(result.map((n) => n.name).toList(), ['small', 'big']);
    });

    test('视频按时长升序', () async {
      final settings = ViewSettings();
      await settings.setVideoSortField(VideoSortField.duration);
      final result = settings.sortTree([
        video('long', duration: 100),
        video('short', duration: 10),
      ]);
      expect(result.map((n) => n.name).toList(), ['short', 'long']);
    });

    test('视频按大小降序', () async {
      final settings = ViewSettings();
      await settings.setVideoSortField(VideoSortField.size);
      await settings.setVideoSortOrder(SortOrder.desc);
      final result = settings.sortTree([
        video('small', size: 10),
        video('big', size: 100),
      ]);
      expect(result.map((n) => n.name).toList(), ['big', 'small']);
    });

    test('递归排序子级', () {
      final settings = ViewSettings();
      final parent = folder('parent', children: [video('b'), video('a')]);
      final result = settings.sortTree([parent]);
      expect(result[0].children.map((c) => c.name).toList(), ['a', 'b']);
    });

    test('排序不修改原列表', () {
      final settings = ViewSettings();
      final input = [video('b'), video('a')];
      final result = settings.sortTree(input);
      expect(input.map((n) => n.name).toList(), ['b', 'a']); // 原列表不变
      expect(result.map((n) => n.name).toList(), ['a', 'b']);
    });
  });

  group('sortFolders / sortVideos', () {
    test('sortFolders 按名称排序', () async {
      final settings = ViewSettings();
      await settings.setSortField(SortField.name);
      final result = settings.sortFolders([folder('b'), folder('a')]);
      expect(result.map((n) => n.name).toList(), ['a', 'b']);
    });

    test('sortVideos 按日期排序', () async {
      final settings = ViewSettings();
      await settings.setVideoSortField(VideoSortField.date);
      final result = settings.sortVideos([
        VideoFile(
          path: '/old.mp4',
          name: 'old',
          dateModified: DateTime(2020),
        ),
        VideoFile(
          path: '/new.mp4',
          name: 'new',
          dateModified: DateTime(2024),
        ),
      ]);
      expect(result.map((v) => v.name).toList(), ['old', 'new']);
    });
  });
}
