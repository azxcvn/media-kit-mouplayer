/// 弹幕自动匹配缓存模型（切集自动匹配弹幕，工作.md 第 7 点）：
/// 用户在自动匹配/网络搜索中选中某一番剧的某一集后，把「番剧 + 完整集列表」
/// 记下来，切到下一集时按文件名集数自动找到对应集并拉取弹幕，无需重复点击
/// 「自动匹配」按钮。
///
/// 纯数据模型（无逻辑、无依赖）；JSON 序列化供
/// `services/danmaku_auto_match_cache_store.dart` 持久化。
library;

import 'package:moumou/models/dandan_models.dart';

class DanmakuAutoMatchCache {
  /// 番剧 id（弹弹Play 内唯一）
  final int animeId;

  /// 番剧标题（展示 / 提示用）
  final String animeTitle;

  /// 选中结果所在的服务器地址；null = 默认弹弹Play 服务器
  final String? serverUrl;

  /// 该番剧的完整集列表（切集时按集数匹配）
  final List<DandanEpisode> episodes;

  const DanmakuAutoMatchCache({
    required this.animeId,
    required this.animeTitle,
    required this.serverUrl,
    required this.episodes,
  });

  Map<String, dynamic> toJson() => {
        'animeId': animeId,
        'animeTitle': animeTitle,
        'serverUrl': serverUrl ?? '',
        'episodes': [
          for (final ep in episodes)
            {'episodeId': ep.episodeId, 'episodeTitle': ep.episodeTitle},
        ],
      };

  static DanmakuAutoMatchCache? fromJson(Map<String, dynamic> json) {
    final animeId = json['animeId'];
    final animeTitle = json['animeTitle'];
    if (animeId is! num || animeTitle is! String) return null;
    final rawEpisodes = json['episodes'];
    final episodes = <DandanEpisode>[];
    if (rawEpisodes is List) {
      for (final e in rawEpisodes) {
        if (e is Map) {
          final ep = DandanEpisode.fromJson(e.cast<String, dynamic>());
          if (ep != null) episodes.add(ep);
        }
      }
    }
    final rawUrl = json['serverUrl'];
    return DanmakuAutoMatchCache(
      animeId: animeId.toInt(),
      animeTitle: animeTitle,
      serverUrl: (rawUrl is String && rawUrl.isNotEmpty) ? rawUrl : null,
      episodes: episodes,
    );
  }
}
