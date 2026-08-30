/// 弹幕网络服务（弹弹Play 开放弹幕网络业务层，无 UI）：
/// - 搜索：遍历所有**已启用**的弹幕服务器并合并结果（按 animeId 去重，
///   记录每条结果的来源服务器），供网络弹幕搜索页展示；
/// - 自动匹配：对当前视频文件（前 16MB MD5 + 文件名 + 大小）向所有启用
///   服务器发起匹配，合并候选；
/// - 下载：按 episodeId 拉取单集弹幕，转成本地 [DanmakuEntry] 并生成
///   B站 XML 落盘到 `filesDir/danmaku/network/`（持久化记忆用，重启播放/
///   软件后与本地弹幕同一恢复路径）；
/// - 文件哈希：计算文件前 16MB 的 MD5（弹弹Play 匹配接口的约定）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/services/dandan_play_api.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:moumou/utils/dandan_comment.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 搜索结果条目（番剧 + 来源服务器；搜索合并时按 animeId 去重，先到先得）。
class DanmakuSearchItem {
  final DandanAnime anime;

  /// 来源服务器地址；null = 默认弹弹Play 服务器
  final String? serverUrl;

  /// 来源服务器名称（搜索结果胶囊标签展示；默认服务器不在 UI 单独标注）
  final String serverName;

  const DanmakuSearchItem({
    required this.anime,
    required this.serverUrl,
    required this.serverName,
  });
}

/// 搜索合并结果（空结果时 [errors] 记录各服务器失败原因，供 UI 提示）。
class DanmakuSearchResult {
  final List<DanmakuSearchItem> items;
  final List<String> errors;

  const DanmakuSearchResult({required this.items, required this.errors});
}

/// 自动匹配候选（匹配信息 + 来源服务器名/地址）。
class DanmakuMatchItem {
  final DandanMatchInfo match;
  final String serverName;

  /// 来源服务器地址；null = 默认弹弹Play 服务器
  final String? serverUrl;

  const DanmakuMatchItem({
    required this.match,
    required this.serverName,
    required this.serverUrl,
  });
}

/// 网络弹幕落盘文件名（对齐参考项目：非法字符替换为下划线，
/// 保留中文/字母/数字/下划线，避免文件系统差异）。
String networkDanmakuFileName(
  String animeTitle,
  String episodeTitle,
  int episodeId,
) {
  final raw = '${animeTitle}_${episodeTitle}_$episodeId';
  final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\u4e00-\u9fa5]'), '_');
  return '$safe.xml';
}

class DanmakuNetworkService {
  DanmakuNetworkService({DandanPlayApi? api}) : _api = api ?? DandanPlayApi();

  final DandanPlayApi _api;
  final DanmakuServerSettings _serverSettings =
      DanmakuServerSettings.instance;

  /// 测试用：覆盖落盘目录解析（默认 `getApplicationSupportDirectory` 在
  /// 单元测试环境无平台通道会失败，注入临时目录即可验证落盘逻辑）。
  @visibleForTesting
  static Future<Directory?> Function()? debugDirectoryOverride;

  /// 搜索番剧：合并所有已启用服务器的结果（animeId 去重，先到先得）。
  Future<DanmakuSearchResult> search(String keyword) async {
    final items = <DanmakuSearchItem>[];
    final seenIds = <int>{};
    final errors = <String>[];
    for (final server in _serverSettings.enabledServers) {
      try {
        final serverUrl = server.isDefault ? null : server.url;
        final animes = await _api.searchAnime(keyword, baseUrl: serverUrl);
        for (final anime in animes) {
          if (seenIds.add(anime.animeId)) {
            items.add(DanmakuSearchItem(
              anime: anime,
              serverUrl: serverUrl,
              serverName: server.name,
            ));
          }
        }
      } catch (e) {
        errors.add('${server.name}: ${e is DandanApiException ? e.message : e}');
      }
    }
    return DanmakuSearchResult(items: items, errors: errors);
  }

  /// 文件匹配：合并所有已启用服务器的候选（按 episodeId 去重）。
  Future<List<DanmakuMatchItem>> matchVideo({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    final items = <DanmakuMatchItem>[];
    final seenIds = <int>{};
    for (final server in _serverSettings.enabledServers) {
      try {
        final serverUrl = server.isDefault ? null : server.url;
        final matches = await _api.matchDanmaku(
          fileName: fileName,
          fileHash: fileHash,
          fileSize: fileSize,
          baseUrl: serverUrl,
        );
        for (final match in matches) {
          if (seenIds.add(match.episodeId)) {
            items.add(DanmakuMatchItem(
              match: match,
              serverName: server.name,
              serverUrl: serverUrl,
            ));
          }
        }
      } catch (_) {
        // 单服务器失败不阻断整体（其余服务器结果仍可用）
      }
    }
    return items;
  }

  /// 下载单集弹幕：拉取评论 → 转本地条目 + 生成 B站 XML **落盘**
  /// （`filesDir/danmaku/network/`，与原生手动导入目录同级）。
  ///
  /// 返回条目与落盘路径；落盘失败不影响本次播放（[filePathOrNull] 为
  /// null，条目仍会装载）。条目为空时不落盘（空弹幕文件无记忆价值）。
  Future<({List<DanmakuEntry> entries, String? filePathOrNull})>
      downloadEpisode({
    required int episodeId,
    required String animeTitle,
    required String episodeTitle,
    String? serverUrl,
  }) async {
    final comments = await _api.getComments(episodeId, baseUrl: serverUrl);
    final entries = dandanCommentsToEntries(comments);
    if (entries.isEmpty) {
      return (entries: const <DanmakuEntry>[], filePathOrNull: null);
    }
    final xml = dandanCommentsToXml(comments);
    final path = await _saveXml(
      xml,
      networkDanmakuFileName(animeTitle, episodeTitle, episodeId),
    );
    return (entries: entries, filePathOrNull: path);
  }

  /// 通过番剧名搜索并取回指定 animeId 的完整集列表（自动匹配命中后保存
  /// 切集缓存用）；找不到返回 null。
  Future<List<DandanEpisode>?> fetchAnimeEpisodesById(
    int animeId,
    String animeTitle, {
    String? serverUrl,
  }) async {
    final animes = await _api.searchAnime(animeTitle, baseUrl: serverUrl);
    for (final anime in animes) {
      if (anime.animeId == animeId) return anime.episodes;
    }
    return null;
  }

  /// 计算文件前 16MB 的 MD5（弹弹Play 匹配接口约定）；失败返回 null。
  Future<String?> calculateFileHash(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final length = await file.length();
      final readSize =
          length < 16 * 1024 * 1024 ? length : 16 * 1024 * 1024;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, readSize)) {
        builder.add(chunk);
      }
      return md5.convert(builder.takeBytes()).toString();
    } catch (_) {
      return null;
    }
  }

  // ── 落盘（网络弹幕持久化，工作.md 第 2 点）──────────────────

  /// 落盘目录：`filesDir/danmaku/network/`（getApplicationSupportDirectory
  /// 在 Android 上即 filesDir，与原生手动导入的 danmaku/ 目录同级）。
  Future<Directory?> _danmakuDir() async {
    final override = debugDirectoryOverride;
    if (override != null) return override();
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'danmaku', 'network'));
    } catch (_) {
      return null;
    }
  }

  /// 写入 XML 文件，返回真实路径；失败返回 null（不阻断本次播放）。
  Future<String?> _saveXml(String xml, String fileName) async {
    try {
      final dir = await _danmakuDir();
      if (dir == null) return null;
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(xml, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
