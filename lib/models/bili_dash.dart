/// 哔哩哔哩 playurl（DASH 流）数据模型。
///
/// 字段语义对齐 PiliPlus `models/video/play/url.dart`，但按本项目
/// 「防御式解析」约定实现：数字字段兼容 num/String；URL 兼容旧
/// `baseUrl`/`base_url` 与新 `baseUrls[]`（字符串数组或对象数组）两种
/// 结构——PiliPlus 只认前者，遇到新格式会拿到空 URL，这是需要规避的坑。
library;

/// 数字字段防御式解析：B 站部分接口把数字字段返回成字符串。
int _asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

List<String> _asStringList(Object? v) {
  if (v is List) return v.whereType<String>().toList();
  return const [];
}

/// 从流条目 JSON 提取主 URL 与备份 URL 列表。
///
/// 兼容三种结构：
/// 1. `baseUrl`/`base_url`（字符串）+ `backupUrl`/`backup_url`（字符串数组）；
/// 2. `baseUrls`（字符串数组，首项为主、其余为备份）；
/// 3. `baseUrls`（对象数组，首项的 `base_url` 为主、`backup_url` 为备份）。
(String, List<String>) _extractUrls(Map<String, dynamic> json) {
  var primary = (json['baseUrl'] ?? json['base_url'])?.toString() ?? '';
  final backups = <String>[];

  void collectBackup(Object? v) {
    if (v is List) {
      backups.addAll(v.whereType<String>());
    } else if (v is String && v.isNotEmpty) {
      backups.add(v);
    }
  }

  collectBackup(json['backupUrl']);
  collectBackup(json['backup_url']);

  if (primary.isEmpty) {
    final baseUrls = json['baseUrls'] ?? json['base_urls'];
    if (baseUrls is List && baseUrls.isNotEmpty) {
      final first = baseUrls.first;
      if (first is String) {
        primary = first;
        for (final e in baseUrls.skip(1)) {
          if (e is String) backups.add(e);
        }
      } else if (first is Map) {
        primary = (first['baseUrl'] ?? first['base_url'])?.toString() ?? '';
        collectBackup(first['backupUrl'] ?? first['backup_url']);
      }
    }
  }
  return (primary, backups);
}

/// 画质档位（`accept_quality` 与 `accept_description` 按下标对齐）。
class BiliQualityOption {
  final int qn;
  final String description;

  const BiliQualityOption({required this.qn, required this.description});
}

/// OP/ED 等跳段信息（playurl 响应 `clip_info_list[]`，`start`/`end` 单位秒）。
class BiliClipInfo {
  final double startSeconds;
  final double endSeconds;
  final String clipType;

  const BiliClipInfo({
    required this.startSeconds,
    required this.endSeconds,
    required this.clipType,
  });

  bool get isOp => clipType == 'CLIP_TYPE_OP';
  bool get isEd => clipType == 'CLIP_TYPE_ED';

  factory BiliClipInfo.fromJson(Map<String, dynamic> json) => BiliClipInfo(
        startSeconds: _asDouble(json['start']),
        endSeconds: _asDouble(json['end']),
        clipType: (json['clipType'] ?? json['clip_type'])?.toString() ?? '',
      );
}

/// DASH 流条目（视频/音频共用字段）。
class BiliDashStream {
  /// 视频为画质 qn；音频为音质 id（30280=192K 等）。
  final int id;
  final String baseUrl;
  final List<String> backupUrls;
  final int bandwidth;
  final String mimeType;
  final String codecs;
  final int width;
  final int height;
  final String frameRate;

  const BiliDashStream({
    required this.id,
    required this.baseUrl,
    this.backupUrls = const [],
    this.bandwidth = 0,
    this.mimeType = '',
    this.codecs = '',
    this.width = 0,
    this.height = 0,
    this.frameRate = '',
  });

  factory BiliDashStream.fromJson(Map<String, dynamic> json) {
    final urls = _extractUrls(json);
    return BiliDashStream(
      id: _asInt(json['id']),
      baseUrl: urls.$1,
      backupUrls: urls.$2,
      bandwidth: _asInt(json['bandwidth'] ?? json['bandWidth']),
      mimeType: (json['mimeType'] ?? json['mime_type'])?.toString() ?? '',
      codecs: json['codecs']?.toString() ?? '',
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      frameRate:
          (json['frameRate'] ?? json['frame_rate'])?.toString() ?? '',
    );
  }
}

/// playurl 解析结果（PGC v2 响应在 `result.video_info` 下，UGC 在 `data` 下，
/// 二者经各自 service 归一后都套用本模型）。
class BiliPlayUrlResult {
  final int quality;
  final String format;
  final int timelength; // 毫秒
  final List<String> acceptDescription;
  final List<int> acceptQuality;
  final List<BiliDashStream> videos;
  final List<BiliDashStream> audios;
  final List<BiliClipInfo> clips;

  const BiliPlayUrlResult({
    required this.quality,
    this.format = '',
    this.timelength = 0,
    this.acceptDescription = const [],
    this.acceptQuality = const [],
    this.videos = const [],
    this.audios = const [],
    this.clips = const [],
  });

  /// 当前账号可选的画质档（供「更多 → 清晰度」面板展示）。
  List<BiliQualityOption> get qualityOptions {
    final options = <BiliQualityOption>[];
    for (var i = 0; i < acceptQuality.length; i++) {
      final desc = i < acceptDescription.length
          ? acceptDescription[i]
          : '${acceptQuality[i]}P';
      options.add(BiliQualityOption(qn: acceptQuality[i], description: desc));
    }
    return options;
  }

  /// 默认视频流：B 站 playurl 的 `dash.video` 可能返回全部档位（降序），
  /// 直接取首项会永远选中最高档、导致「切低画质」不生效。优先取与请求画质
  /// [quality] 一致的流，取不到再回退首项。
  BiliDashStream? get defaultVideo {
    if (videos.isEmpty) return null;
    for (final v in videos) {
      if (v.id == quality) return v;
    }
    return videos.first;
  }

  /// 默认音频流：优先 192K（30280），否则取首项。
  BiliDashStream? get defaultAudio {
    if (audios.isEmpty) return null;
    for (final a in audios) {
      if (a.id == 30280) return a;
    }
    return audios.first;
  }

  factory BiliPlayUrlResult.fromJson(Map<String, dynamic> json) {
    final dash = json['dash'];
    final dashMap = dash is Map
        ? dash.cast<String, dynamic>()
        : const <String, dynamic>{};
    final videoList = (dashMap['video'] as List?) ?? const [];

    final audios = <BiliDashStream>[];
    final flac = dashMap['flac'];
    if (flac is Map && flac['audio'] is Map) {
      audios.add(BiliDashStream.fromJson(
        (flac['audio'] as Map).cast<String, dynamic>(),
      ));
    }
    final dolby = dashMap['dolby'];
    if (dolby is Map && dolby['audio'] is List) {
      for (final a in dolby['audio']) {
        if (a is Map) {
          audios.add(BiliDashStream.fromJson(a.cast<String, dynamic>()));
        }
      }
    }
    final audioList = (dashMap['audio'] as List?) ?? const [];
    for (final a in audioList) {
      if (a is Map) {
        audios.add(BiliDashStream.fromJson(a.cast<String, dynamic>()));
      }
    }

    final clipList = (json['clip_info_list'] as List?) ?? const [];
    return BiliPlayUrlResult(
      quality: _asInt(json['quality']),
      format: json['format']?.toString() ?? '',
      timelength: _asInt(json['timelength']),
      acceptDescription: _asStringList(json['accept_description']),
      acceptQuality: (json['accept_quality'] as List?)
              ?.map((e) => _asInt(e))
              .toList() ??
          const [],
      videos: videoList
          .whereType<Map>()
          .map((e) => BiliDashStream.fromJson(e.cast<String, dynamic>()))
          .toList(),
      audios: audios,
      clips: clipList
          .whereType<Map>()
          .map((e) => BiliClipInfo.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// UGC 视频单个分 P（`/x/web-interface/view` 的 `pages[]` 条目）。
class BiliUgcPage {
  final int cid;
  final int page; // 分 P 序号（从 1 开始）
  final String part; // 分 P 标题
  final int durationMs;

  const BiliUgcPage({
    required this.cid,
    required this.page,
    required this.part,
    this.durationMs = 0,
  });

  factory BiliUgcPage.fromJson(Map<String, dynamic> json) => BiliUgcPage(
        cid: _asInt(json['cid']),
        page: _asInt(json['page']),
        part: json['part']?.toString() ?? '',
        durationMs: _asInt(json['duration']) * 1000,
      );
}

/// UGC 视频详情（`/x/web-interface/view` 解析结果的最小集：标题 + 全部分 P）。
class BiliUgcVideo {
  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final int durationMs;

  /// 全部分 P（老项目只取 `pages[0]`，多 P 视频只能下到第一段——这里补全）。
  final List<BiliUgcPage> pages;

  /// UP 主合集（`ugc_season`）：视频属于某个合集时返回，含全部章节/集/分P。
  final BiliUgcSeason? ugcSeason;

  const BiliUgcVideo({
    required this.aid,
    required this.bvid,
    required this.cid,
    this.title = '',
    this.durationMs = 0,
    this.pages = const [],
    this.ugcSeason,
  });

  factory BiliUgcVideo.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as List?)
            ?.whereType<Map>()
            .map((e) => BiliUgcPage.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
    final first = pages.isNotEmpty ? pages.first : null;
    final ugcSeason = json['ugc_season'];
    return BiliUgcVideo(
      aid: _asInt(json['aid']),
      bvid: json['bvid']?.toString() ?? '',
      cid: first?.cid ?? 0,
      title: json['title']?.toString() ?? '',
      durationMs: first?.durationMs ?? _asInt(json['duration']) * 1000,
      pages: pages,
      ugcSeason: ugcSeason is Map
          ? BiliUgcSeason.fromJson(ugcSeason.cast<String, dynamic>())
          : null,
    );
  }
}

/// UP 主合集（`view` 接口的 `ugc_season`）：标题 + 封面 + 分章节的集列表。
class BiliUgcSeason {
  final int seasonId;
  final String title;
  final String cover;
  final List<BiliUgcSeasonSection> sections;

  const BiliUgcSeason({
    required this.seasonId,
    this.title = '',
    this.cover = '',
    this.sections = const [],
  });

  factory BiliUgcSeason.fromJson(Map<String, dynamic> json) {
    final sections = (json['sections'] as List?)
            ?.whereType<Map>()
            .map((e) => BiliUgcSeasonSection.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
    return BiliUgcSeason(
      seasonId: _asInt(json['id']),
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      sections: sections,
    );
  }
}

/// 合集章节（`sections[]`）：标题 + 该章节下的集列表。
class BiliUgcSeasonSection {
  final int sectionId;
  final String title;
  final List<BiliUgcSeasonEpisode> episodes;

  const BiliUgcSeasonSection({
    required this.sectionId,
    this.title = '',
    this.episodes = const [],
  });

  factory BiliUgcSeasonSection.fromJson(Map<String, dynamic> json) {
    final episodes = (json['episodes'] as List?)
            ?.whereType<Map>()
            .map((e) => BiliUgcSeasonEpisode.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
    return BiliUgcSeasonSection(
      sectionId: _asInt(json['id']),
      title: json['title']?.toString() ?? '',
      episodes: episodes,
    );
  }
}

/// 合集单集（`episodes[]`）：一个独立 BV，可能自身多分 P（`pages[]`）。
class BiliUgcSeasonEpisode {
  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final List<BiliUgcPage> pages;
  final String cover;
  final int durationMs;

  const BiliUgcSeasonEpisode({
    required this.aid,
    required this.bvid,
    required this.cid,
    this.title = '',
    this.pages = const [],
    this.cover = '',
    this.durationMs = 0,
  });

  factory BiliUgcSeasonEpisode.fromJson(Map<String, dynamic> json) {
    final arc = json['arc'];
    final arcMap = arc is Map ? arc.cast<String, dynamic>() : const <String, dynamic>{};
    final pages = (json['pages'] as List?)
            ?.whereType<Map>()
            .map((e) => BiliUgcPage.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
    return BiliUgcSeasonEpisode(
      aid: _asInt(json['aid']),
      bvid: json['bvid']?.toString() ?? '',
      cid: _asInt(json['cid']),
      title: json['title']?.toString() ?? '',
      pages: pages,
      cover: arcMap['pic']?.toString() ?? '',
      durationMs: _asInt(json['duration'] ?? arcMap['duration']) * 1000,
    );
  }
}
