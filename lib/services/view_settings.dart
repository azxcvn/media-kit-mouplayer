import 'package:flutter/material.dart';
import 'package:moumou/models/tree_node.dart';
import 'package:moumou/models/video_file.dart';
import 'package:moumou/utils/natural_compare.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 排序维度
enum SortField {
  name('名称'),
  date('日期'),
  size('大小'),
  count('数量');

  final String label;
  const SortField(this.label);
}

/// 排序方向
enum SortOrder {
  asc('升序'),
  desc('降序');

  final String label;
  const SortOrder(this.label);
}

/// 文件夹列表显示模式
enum ViewMode {
  tree('树状模式'),
  list('列表模式');

  final String label;
  const ViewMode(this.label);
}

/// 文件夹列表可显示的字段（名称固定显示，不在此列）
enum FolderField {
  path('路径'),
  count('数量'),
  size('大小'),
  date('日期');

  final String label;
  const FolderField(this.label);
}

/// 视频列表可显示的字段（名称固定显示，不在此列）
enum VideoField {
  duration('时长'),
  size('大小'),
  date('日期'),
  resolution('分辨率');

  final String label;
  const VideoField(this.label);
}

/// 视频列表排序维度
enum VideoSortField {
  name('名称'),
  date('日期'),
  size('大小'),
  duration('时长');

  final String label;
  const VideoSortField(this.label);
}

/// 视图设置控制器：管理排序偏好，并持久化
class ViewSettings extends ChangeNotifier {
  static const _keySortField = 'view_sort_field';
  static const _keySortOrder = 'view_sort_order';
  static const _keyFields = 'view_folder_fields';
  static const _keyVideoSortField = 'view_video_sort_field';
  static const _keyVideoSortOrder = 'view_video_sort_order';
  static const _keyVideoFields = 'view_video_fields';
  static const _keyViewMode = 'view_mode';

  SortField _sortField = SortField.name;
  SortOrder _sortOrder = SortOrder.asc;
  Set<FolderField> _fields = {FolderField.count, FolderField.size};

  VideoSortField _videoSortField = VideoSortField.name;
  SortOrder _videoSortOrder = SortOrder.asc;
  Set<VideoField> _videoFields = {VideoField.duration, VideoField.size};

  ViewMode _viewMode = ViewMode.list;

  SortField get sortField => _sortField;
  SortOrder get sortOrder => _sortOrder;
  Set<FolderField> get fields => _fields;
  VideoSortField get videoSortField => _videoSortField;
  SortOrder get videoSortOrder => _videoSortOrder;
  Set<VideoField> get videoFields => _videoFields;
  ViewMode get viewMode => _viewMode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sf = prefs.getInt(_keySortField);
    final so = prefs.getInt(_keySortOrder);
    final fieldsList = prefs.getStringList(_keyFields);
    final vsf = prefs.getInt(_keyVideoSortField);
    final vso = prefs.getInt(_keyVideoSortOrder);
    final videoFieldsList = prefs.getStringList(_keyVideoFields);
    final viewMode = prefs.getInt(_keyViewMode);

    if (sf != null && sf >= 0 && sf < SortField.values.length) {
      _sortField = SortField.values[sf];
    }
    if (so != null && so >= 0 && so < SortOrder.values.length) {
      _sortOrder = SortOrder.values[so];
    }
    if (fieldsList != null && fieldsList.isNotEmpty) {
      _fields = fieldsList
          .map((e) => FolderField.values[int.tryParse(e) ?? 0])
          .toSet();
    }
    if (vsf != null && vsf >= 0 && vsf < VideoSortField.values.length) {
      _videoSortField = VideoSortField.values[vsf];
    }
    if (vso != null && vso >= 0 && vso < SortOrder.values.length) {
      _videoSortOrder = SortOrder.values[vso];
    }
    if (videoFieldsList != null && videoFieldsList.isNotEmpty) {
      _videoFields = videoFieldsList
          .map((e) => VideoField.values[int.tryParse(e) ?? 0])
          .toSet();
    }
    if (viewMode != null && viewMode >= 0 && viewMode < ViewMode.values.length) {
      _viewMode = ViewMode.values[viewMode];
    }
    notifyListeners();
  }

  Future<void> setSortField(SortField v) async {
    if (_sortField == v) return;
    _sortField = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySortField, v.index);
  }

  Future<void> setSortOrder(SortOrder v) async {
    if (_sortOrder == v) return;
    _sortOrder = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySortOrder, v.index);
  }

  /// 切换某个字段的显示/隐藏
  Future<void> toggleField(FolderField f) async {
    if (_fields.contains(f)) {
      _fields.remove(f);
    } else {
      _fields.add(f);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyFields,
      _fields.map((e) => e.index.toString()).toList(),
    );
  }

  Future<void> setVideoSortField(VideoSortField v) async {
    if (_videoSortField == v) return;
    _videoSortField = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVideoSortField, v.index);
  }

  Future<void> setVideoSortOrder(SortOrder v) async {
    if (_videoSortOrder == v) return;
    _videoSortOrder = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVideoSortOrder, v.index);
  }

  /// 切换视频列表某个字段的显示/隐藏
  Future<void> toggleVideoField(VideoField f) async {
    if (_videoFields.contains(f)) {
      _videoFields.remove(f);
    } else {
      _videoFields.add(f);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyVideoFields,
      _videoFields.map((e) => e.index.toString()).toList(),
    );
  }

  /// 设置显示模式（树状/列表）
  Future<void> setViewMode(ViewMode v) async {
    if (_viewMode == v) return;
    _viewMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyViewMode, v.index);
  }

  /// 按当前设置对文件夹列表排序（返回新列表）
  List<TreeNode> sortFolders(List<TreeNode> folders) {
    final list = [...folders];
    _sortFolderList(list);
    return list;
  }

  /// 按当前设置对视频列表排序（返回新列表）
  List<VideoFile> sortVideos(List<VideoFile> videos) {
    final list = [...videos];
    list.sort((a, b) {
      final cmp = _compareVideoFile(a, b);
      return _videoSortOrder == SortOrder.asc ? cmp : -cmp;
    });
    return list;
  }

  /// 树状节点混合排序：文件夹在前、视频在后（与 buildTree 结构一致）。
  /// 文件夹按文件夹排序规则（SortField×SortOrder），视频按视频排序规则
  /// （VideoSortField×VideoSortOrder），递归作用于全部层级。
  List<TreeNode> sortTree(List<TreeNode> nodes) {
    final folders = <TreeNode>[];
    final videos = <TreeNode>[];
    for (final n in nodes) {
      if (n.isFolder) {
        folders.add(_sortFolderNode(n)); // 递归排序其 children
      } else {
        videos.add(n);
      }
    }
    _sortFolderList(folders);
    _sortVideoList(videos);
    return [...folders, ...videos];
  }

  /// 递归排序文件夹节点的子级（返回重建的节点）
  TreeNode _sortFolderNode(TreeNode n) {
    if (n.children.isEmpty) return n;
    return TreeNode(
      name: n.name,
      path: n.path,
      type: n.type,
      children: sortTree(n.children),
      videoCount: n.videoCount,
      totalSize: n.totalSize,
      dateModified: n.dateModified,
    );
  }

  void _sortFolderList(List<TreeNode> folders) {
    folders.sort((a, b) {
      final cmp = _compareFolders(a, b);
      return _sortOrder == SortOrder.asc ? cmp : -cmp;
    });
  }

  void _sortVideoList(List<TreeNode> videos) {
    videos.sort((a, b) {
      final cmp = _compareVideos(a, b);
      return _videoSortOrder == SortOrder.asc ? cmp : -cmp;
    });
  }

  int _compareFolders(TreeNode a, TreeNode b) {
    return switch (_sortField) {
      // 名称用自然序（数字感知）：「第2话」<「第12话」<「第112话」
      SortField.name => naturalCompare(a.name, b.name),
      SortField.date =>
        (a.dateModified?.millisecondsSinceEpoch ?? 0).compareTo(
          b.dateModified?.millisecondsSinceEpoch ?? 0,
        ),
      SortField.size => a.totalSize.compareTo(b.totalSize),
      SortField.count => a.videoCount.compareTo(b.videoCount),
    };
  }

  /// 树状视频节点比较（video 节点恒有 video 值）
  int _compareVideos(TreeNode a, TreeNode b) {
    return _compareVideoFile(a.video!, b.video!);
  }

  int _compareVideoFile(VideoFile a, VideoFile b) {
    return switch (_videoSortField) {
      // 名称用自然序（数字感知）：「2.mp4」<「12.mp4」<「112.mp4」
      VideoSortField.name => naturalCompare(a.name, b.name),
      VideoSortField.date =>
        (a.dateModified?.millisecondsSinceEpoch ?? 0).compareTo(
          b.dateModified?.millisecondsSinceEpoch ?? 0,
        ),
      VideoSortField.size => a.size.compareTo(b.size),
      VideoSortField.duration => a.durationMs.compareTo(b.durationMs),
    };
  }
}
