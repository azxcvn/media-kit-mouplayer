import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文件夹黑白名单过滤模式
enum FolderFilterMode {
  /// 全部扫描：不限制文件夹
  none,

  /// 黑名单模式：排除指定文件夹及其子目录
  blacklist,

  /// 白名单模式：仅扫描指定文件夹及其子目录
  whitelist;

  String get label => switch (this) {
        FolderFilterMode.none => '全部扫描',
        FolderFilterMode.blacklist => '黑名单模式（排除以下文件夹）',
        FolderFilterMode.whitelist => '白名单模式（仅扫描以下文件夹）',
      };

  String get subtitle => switch (this) {
        FolderFilterMode.none => '扫描设备上所有未被规则跳过的媒体文件夹',
        FolderFilterMode.blacklist => '指定文件夹内的视频将不会显示在媒体列表中',
        FolderFilterMode.whitelist => '仅显示指定文件夹内的视频，其他文件夹将被忽略',
      };

  static FolderFilterMode byName(String? name) {
    return FolderFilterMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => FolderFilterMode.none,
    );
  }
}

/// 媒体扫描与过滤设置（单例模式，ChangeNotifier + SharedPreferences 持久化）
///
/// 包含：
/// 1. 扫描包含 `.nomedia` 的文件夹（默认关闭，跳过 .nomedia 目录）；
/// 2. 扫描以 `.` 开头的隐藏文件夹（默认关闭，跳过 .开头 隐藏项）；
/// 3. 文件夹黑白名单过滤（全部扫描 / 黑名单模式 / 白名单模式）；
/// 4. 黑名单 / 白名单文件夹路径列表维护。
class MediaScanSettings extends ChangeNotifier {
  static MediaScanSettings? _instance;
  static MediaScanSettings get instance =>
      _instance ??= MediaScanSettings._();

  /// 仅用于扫描全部视频的静态无过滤实例
  static final MediaScanSettings unfiltered = MediaScanSettings._();

  MediaScanSettings._();

  static const _keyScanNoMedia = 'media_scan_no_media';
  static const _keyScanHiddenFolders = 'media_scan_hidden_folders';
  static const _keyFilterMode = 'media_scan_filter_mode';
  static const _keyBlacklist = 'media_scan_blacklist_folders';
  static const _keyWhitelist = 'media_scan_whitelist_folders';

  bool _scanNoMedia = false;
  bool _scanHiddenFolders = false;
  FolderFilterMode _filterMode = FolderFilterMode.none;
  List<String> _blacklistFolders = [];
  List<String> _whitelistFolders = [];

  Future<void>? _loadFuture;

  bool get scanNoMedia => _scanNoMedia;
  bool get scanHiddenFolders => _scanHiddenFolders;
  FolderFilterMode get filterMode => _filterMode;
  List<String> get blacklistFolders => List.unmodifiable(_blacklistFolders);
  List<String> get whitelistFolders => List.unmodifiable(_whitelistFolders);

  /// 确保已从 SharedPreferences 完成加载
  Future<void> ensureLoaded() => _loadFuture ??= load();

  /// 从持久化加载所有设置
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _scanNoMedia = prefs.getBool(_keyScanNoMedia) ?? false;
    _scanHiddenFolders = prefs.getBool(_keyScanHiddenFolders) ?? false;
    _filterMode = FolderFilterMode.byName(prefs.getString(_keyFilterMode));
    _blacklistFolders = prefs.getStringList(_keyBlacklist) ?? [];
    _whitelistFolders = prefs.getStringList(_keyWhitelist) ?? [];
    notifyListeners();
  }

  /// 切换「扫描包含 .nomedia 的文件夹」
  Future<void> setScanNoMedia(bool value) async {
    await ensureLoaded();
    if (_scanNoMedia == value) return;
    _scanNoMedia = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScanNoMedia, value);
  }

  /// 切换「扫描以 . 开头的隐藏文件夹」
  Future<void> setScanHiddenFolders(bool value) async {
    await ensureLoaded();
    if (_scanHiddenFolders == value) return;
    _scanHiddenFolders = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScanHiddenFolders, value);
  }

  /// 切换黑白名单过滤模式
  Future<void> setFilterMode(FolderFilterMode mode) async {
    await ensureLoaded();
    if (_filterMode == mode) return;
    _filterMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFilterMode, mode.name);
  }

  /// 添加一个黑名单文件夹
  Future<void> addBlacklistFolder(String folderPath) async {
    final norm = _normalizePath(folderPath);
    if (norm.isEmpty) return;
    await ensureLoaded();
    if (!_blacklistFolders.contains(norm)) {
      _blacklistFolders = [..._blacklistFolders, norm];
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyBlacklist, _blacklistFolders);
    }
  }

  /// 移除一个黑名单文件夹
  Future<void> removeBlacklistFolder(String folderPath) async {
    final norm = _normalizePath(folderPath);
    await ensureLoaded();
    if (_blacklistFolders.contains(norm)) {
      _blacklistFolders =
          _blacklistFolders.where((p) => p != norm).toList();
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyBlacklist, _blacklistFolders);
    }
  }

  /// 添加一个白名单文件夹
  Future<void> addWhitelistFolder(String folderPath) async {
    final norm = _normalizePath(folderPath);
    if (norm.isEmpty) return;
    await ensureLoaded();
    if (!_whitelistFolders.contains(norm)) {
      _whitelistFolders = [..._whitelistFolders, norm];
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyWhitelist, _whitelistFolders);
    }
  }

  /// 移除一个白名单文件夹
  Future<void> removeWhitelistFolder(String folderPath) async {
    final norm = _normalizePath(folderPath);
    await ensureLoaded();
    if (_whitelistFolders.contains(norm)) {
      _whitelistFolders =
          _whitelistFolders.where((p) => p != norm).toList();
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyWhitelist, _whitelistFolders);
    }
  }

  /// 判定某个视频或文件夹路径是否符合当前的黑白名单过滤规则
  ///
  /// - `FolderFilterMode.none`：全部允许通过；
  /// - `FolderFilterMode.blacklist`：只要命中黑名单文件夹（或其子路径），返回 false；
  /// - `FolderFilterMode.whitelist`：仅命中白名单文件夹（或其子路径）时返回 true，未配置白名单时默认放行。
  bool isPathAllowed(String path) {
    if (path.isEmpty) return true;
    final norm = _normalizePath(path);

    switch (_filterMode) {
      case FolderFilterMode.none:
        return true;

      case FolderFilterMode.blacklist:
        for (final b in _blacklistFolders) {
          if (_isSubPathOrSame(norm, b)) {
            return false;
          }
        }
        return true;

      case FolderFilterMode.whitelist:
        if (_whitelistFolders.isEmpty) return true;
        for (final w in _whitelistFolders) {
          if (_isSubPathOrSame(norm, w)) {
            return true;
          }
        }
        return false;
    }
  }

  /// 判断 targetPath 是否等于 parentPath 或为 parentPath 的子级
  static bool _isSubPathOrSame(String targetPath, String parentPath) {
    final t = _normalizePath(targetPath);
    final p = _normalizePath(parentPath);
    if (t == p) return true;
    return t.startsWith('$p/');
  }

  /// 归一化路径：转为小写、折叠多余斜杠、去掉尾部斜杠
  static String _normalizePath(String? path) {
    if (path == null) return '';
    var raw = path.trim().replaceAll('\\', '/');
    raw = raw.replaceAll(RegExp(r'/+'), '/');
    if (raw.length > 1 && raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  /// 测试用：重置所有状态
  @visibleForTesting
  void reset() {
    _loadFuture = null;
    _scanNoMedia = false;
    _scanHiddenFolders = false;
    _filterMode = FolderFilterMode.none;
    _blacklistFolders = [];
    _whitelistFolders = [];
    notifyListeners();
  }
}
