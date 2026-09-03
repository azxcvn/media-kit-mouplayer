/// 哔哩哔哩番剧（PGC）域纯数据模型：索引筛选/条目、搜索、季详情/选集/多季、
/// 新番时间表。全部 `fromJson` 容错（字段缺失回退默认值），无逻辑、无依赖。
library;

/// 数值解析：兼容 num 与 String（B 站部分端点把数字字段以字符串下发，直接
/// `as num?` 会触发 "type 'String' is not a subtype of type 'num'" 崩溃）。
int _asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

// ───────────────────────── 索引筛选条件 ─────────────────────────

/// 筛选维度下的一个可选值（keyword = 提交给接口的值，-1 表示「全部」）。
class BiliIndexValue {
  final String keyword;
  final String name;

  const BiliIndexValue({required this.keyword, required this.name});

  factory BiliIndexValue.fromJson(Map<String, dynamic> json) => BiliIndexValue(
        keyword: json['keyword'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// 一个筛选维度（如「地区」「版本」「是否完结」）。
class BiliIndexFilter {
  final String field; // 请求参数名（如 area / season_version）
  final String name; // 展示名
  final List<BiliIndexValue> values;

  const BiliIndexFilter({
    required this.field,
    required this.name,
    required this.values,
  });

  factory BiliIndexFilter.fromJson(Map<String, dynamic> json) =>
      BiliIndexFilter(
        field: json['field'] as String? ?? '',
        name: json['name'] as String? ?? '',
        values: (json['values'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliIndexValue.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// 排序项（condition 接口的 order[]，首项即默认排序）。
class BiliIndexOrder {
  final String field;
  final String name;
  final String sort;

  const BiliIndexOrder({
    required this.field,
    required this.name,
    required this.sort,
  });

  factory BiliIndexOrder.fromJson(Map<String, dynamic> json) => BiliIndexOrder(
        field: json['field'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sort: json['sort'] as String? ?? '',
      );
}

/// 索引筛选条件（condition 接口 `data`）。
class BiliIndexCondition {
  final List<BiliIndexFilter> filters;
  final List<BiliIndexOrder> orders;

  const BiliIndexCondition({required this.filters, required this.orders});

  factory BiliIndexCondition.fromJson(Map<String, dynamic> json) =>
      BiliIndexCondition(
        filters: (json['filter'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliIndexFilter.fromJson(e.cast<String, dynamic>()))
            .toList(),
        orders: (json['order'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliIndexOrder.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

// ───────────────────────── 索引结果 ─────────────────────────

/// 索引列表条目。
class BiliIndexItem {
  final int seasonId;
  final String title;
  final String cover;
  final String indexShow; // 标题下方小字（如「全13话」）
  final String badge; // 封面右上角标（如「独播」「会员」）
  final String order; // 封面左下角灰标（如「更新至第5话」）

  const BiliIndexItem({
    required this.seasonId,
    required this.title,
    required this.cover,
    this.indexShow = '',
    this.badge = '',
    this.order = '',
  });

  factory BiliIndexItem.fromJson(Map<String, dynamic> json) => BiliIndexItem(
        seasonId: _asInt(json['season_id']),
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        indexShow: json['index_show'] as String? ?? '',
        badge: json['badge'] as String? ?? '',
        order: json['order'] as String? ?? '',
      );
}

/// 索引结果（分页）。
class BiliIndexResult {
  final bool hasNext;
  final List<BiliIndexItem> list;

  const BiliIndexResult({required this.hasNext, required this.list});

  factory BiliIndexResult.fromJson(Map<String, dynamic> json) =>
      BiliIndexResult(
        hasNext: _asInt(json['has_next']) != 0,
        list: (json['list'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliIndexItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

// ───────────────────────── 搜索 ─────────────────────────

/// 番剧搜索结果条目（media_bangumi）。
class BiliSearchItem {
  final int seasonId;
  final int mediaId;
  final String title;
  final String cover;
  final String indexShow; // 更新状态
  final String areas; // 地区（逗号分隔）
  final String styles; // 风格（逗号分隔）
  final double mediaScore; // 评分（media_score.score）

  const BiliSearchItem({
    required this.seasonId,
    required this.mediaId,
    required this.title,
    required this.cover,
    this.indexShow = '',
    this.areas = '',
    this.styles = '',
    this.mediaScore = 0,
  });

  factory BiliSearchItem.fromJson(Map<String, dynamic> json) => BiliSearchItem(
        seasonId: _asInt(json['season_id']),
        mediaId: _asInt(json['media_id']),
        title: _stripEm(json['title'] as String? ?? ''),
        cover: json['cover'] as String? ?? '',
        indexShow: json['index_show'] as String? ?? '',
        areas: json['areas'] as String? ?? '',
        styles: json['styles'] as String? ?? '',
        mediaScore: _mediaScore(json['media_score']),
      );

  static double _mediaScore(Object? raw) {
    if (raw is Map) return _asDouble(raw['score']);
    return _asDouble(raw);
  }

  /// 去除搜索结果的 `<em class="keyword">…</em>` 高亮标记。
  static String _stripEm(String s) => s.replaceAll(RegExp(r'</?em[^>]*>'), '');
}

/// 番剧搜索结果。
class BiliSearchResult {
  final int numResults;
  final List<BiliSearchItem> list;

  const BiliSearchResult({required this.numResults, required this.list});

  factory BiliSearchResult.fromJson(Map<String, dynamic> json) =>
      BiliSearchResult(
        numResults: _asInt(json['numResults']),
        list: (json['result'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliSearchItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

// ───────────────────────── 季详情 / 选集 / 多季 ─────────────────────────

/// 单集（episodes 条目）。
class BiliEpisode {
  final int epId;
  final int aid;
  final int cid;
  final String bvid;
  final String title; // 短标题（如「第1话」）
  final String longTitle; // 长标题（集名，如「第1话 你即将死去」）
  final String cover;
  final int duration; // 毫秒
  final String badge; // 角标（会员 / 限免 / 预告 / 独播…）
  final int badgeType;
  final int status; // 2 可看 / 13 预告等

  const BiliEpisode({
    required this.epId,
    required this.aid,
    required this.cid,
    required this.bvid,
    required this.title,
    required this.longTitle,
    required this.cover,
    this.duration = 0,
    this.badge = '',
    this.badgeType = 0,
    this.status = 0,
  });

  factory BiliEpisode.fromJson(Map<String, dynamic> json) => BiliEpisode(
        epId: _asInt(json['ep_id']),
        aid: _asInt(json['aid']),
        cid: _asInt(json['cid']),
        bvid: json['bvid'] as String? ?? '',
        title: json['title'] as String? ?? '',
        longTitle: json['long_title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        duration: _asInt(json['duration']),
        badge: json['badge'] as String? ?? '',
        badgeType: _asInt(json['badge_type']),
        status: _asInt(json['status']),
      );
}

/// 多季切换条目（seasons 数组）。
class BiliSeason {
  final int seasonId;
  final String seasonTitle;
  final String cover;
  final String badge;

  const BiliSeason({
    required this.seasonId,
    required this.seasonTitle,
    required this.cover,
    this.badge = '',
  });

  factory BiliSeason.fromJson(Map<String, dynamic> json) => BiliSeason(
        seasonId: _asInt(json['season_id']),
        seasonTitle: json['season_title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        badge: json['badge'] as String? ?? '',
      );
}

/// 季详情（season 接口 `result`）。
class BiliSeasonDetail {
  final int seasonId;
  final int mediaId;
  final String title; // 番剧名
  final String cover;
  final String evaluate; // 简介
  final List<String> areas;
  final double ratingScore; // 评分
  final String publishTime; // 开播时间（publish.pub_time_show）
  final int views; // 播放量
  final int danmaku; // 弹幕数
  final int favorite; // 收藏数（stat.favorite）
  final int likes; // 点赞数（stat.likes）
  final int coins; // 投币数（stat.coins）
  final String newEpTitle; // 更新标题（new_ep.title）
  final String newEpDesc; // 更新说明（new_ep.desc，如「更新至第5话」）
  final List<BiliEpisode> episodes;
  final List<BiliSeason> seasons; // 多季

  const BiliSeasonDetail({
    required this.seasonId,
    required this.mediaId,
    required this.title,
    required this.cover,
    required this.evaluate,
    required this.areas,
    required this.ratingScore,
    required this.publishTime,
    required this.views,
    required this.danmaku,
    required this.favorite,
    required this.likes,
    required this.coins,
    required this.newEpTitle,
    required this.newEpDesc,
    required this.episodes,
    required this.seasons,
  });

  factory BiliSeasonDetail.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'];
    final publish = json['publish'];
    final stat = json['stat'];
    final newEp = json['new_ep'];
    return BiliSeasonDetail(
      seasonId: _asInt(json['season_id']),
      mediaId: _asInt(json['media_id']),
      title: json['title'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      evaluate: json['evaluate'] as String? ?? '',
      areas: (json['areas'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => (e['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      ratingScore: rating is Map ? _asDouble(rating['score']) : 0,
      publishTime:
          publish is Map ? publish['pub_time_show'] as String? ?? '' : '',
      views: stat is Map ? _asInt(stat['views']) : 0,
      danmaku: stat is Map ? _asInt(stat['danmakus']) : 0,
      favorite: stat is Map ? _asInt(stat['favorite']) : 0,
      likes: stat is Map ? _asInt(stat['likes']) : 0,
      coins: stat is Map ? _asInt(stat['coins']) : 0,
      newEpTitle: newEp is Map ? newEp['title'] as String? ?? '' : '',
      newEpDesc: newEp is Map ? newEp['desc'] as String? ?? '' : '',
      episodes: (json['episodes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => BiliEpisode.fromJson(e.cast<String, dynamic>()))
          .toList(),
      seasons: (json['seasons'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => BiliSeason.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

// ───────────────────────── 新番时间表 ─────────────────────────

/// 时间表里的单集。
class BiliTimelineEpisode {
  final int episodeId;
  final int seasonId;
  final String title;
  final String cover;
  final String pubIndex; // 集序（如「第5话」）
  final String pubTime; // 放送时间
  final int follow; // 是否已追番（1 = 是）

  const BiliTimelineEpisode({
    required this.episodeId,
    required this.seasonId,
    required this.title,
    required this.cover,
    this.pubIndex = '',
    this.pubTime = '',
    this.follow = 0,
  });

  factory BiliTimelineEpisode.fromJson(Map<String, dynamic> json) =>
      BiliTimelineEpisode(
        episodeId: _asInt(json['episode_id']),
        seasonId: _asInt(json['season_id']),
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        pubIndex: json['pub_index'] as String? ?? '',
        pubTime: json['pub_time'] as String? ?? '',
        follow: _asInt(json['follow']),
      );
}

/// 时间表某一天。
class BiliTimelineDay {
  final String date; // 如「09-01」
  final int dayOfWeek; // 1~7
  final bool isToday;
  final List<BiliTimelineEpisode> episodes;

  const BiliTimelineDay({
    required this.date,
    required this.dayOfWeek,
    required this.isToday,
    required this.episodes,
  });

  factory BiliTimelineDay.fromJson(Map<String, dynamic> json) =>
      BiliTimelineDay(
        date: json['date'] as String? ?? '',
        dayOfWeek: _asInt(json['day_of_week']),
        isToday: _asInt(json['is_today']) != 0,
        episodes: (json['episodes'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => BiliTimelineEpisode.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}
