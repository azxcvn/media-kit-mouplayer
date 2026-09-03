import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 哔哩哔哩下载设置（ChangeNotifier 单例）：下载保存目录。
///
/// 弹幕/视频下载页在开始解析前强制校验目录已设置；目录为用户用目录选择器
/// 选中的**真实路径**（App 持有 MANAGE_EXTERNAL_STORAGE，直接走 `dart:io` 写盘，
/// 无需 SAF content:// 流转）。
class DownloadSettings extends ChangeNotifier {
  DownloadSettings._();
  static final DownloadSettings instance = DownloadSettings._();

  static const String _keyDir = 'bili_download_dir';

  Future<void>? _loadFuture;
  String _directory = '';

  /// 当前下载目录（未设置时为空串）。
  String get directory => _directory;
  bool get hasDirectory => _directory.isNotEmpty;

  /// 目录名（去掉父路径，仅展示最后一级文件夹名，避免用户不知道自己在哪）。
  String get directoryName {
    if (_directory.isEmpty) return '';
    final norm = _directory.endsWith('/')
        ? _directory.substring(0, _directory.length - 1)
        : _directory;
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _directory = prefs.getString(_keyDir) ?? '';
    notifyListeners();
  }

  /// 写入并持久化下载目录。
  Future<void> setDirectory(String path) async {
    _directory = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDir, path);
  }
}
