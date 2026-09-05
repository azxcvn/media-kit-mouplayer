import 'package:http/http.dart' as http;
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/bili_video_service.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';
import 'package:moumou/utils/bili_short_link.dart';

/// 解析出的单个可下载条目（番剧单集 / UGC 单个分 P）。
class BiliDownloadItem {
  final String title;
  final int aid;
  final int cid;
  final int epId;
  final int seasonId;
  final String bvid;

  const BiliDownloadItem({
    required this.title,
    required this.aid,
    required this.cid,
    this.epId = 0,
    this.seasonId = 0,
    this.bvid = '',
  });
}

/// 链接解析目标：一组可下载条目（番剧多集 / UGC 多分 P）。
class BiliDownloadTarget {
  final String title;
  final String cover;
  final bool isBangumi;
  final List<BiliDownloadItem> items;

  const BiliDownloadTarget({
    required this.title,
    required this.cover,
    required this.isBangumi,
    required this.items,
  });
}

/// 哔哩哔哩下载解析服务：把用户粘贴的链接解析成可下载条目列表。
///
/// 番剧（`ss`/`ep`）→ 季详情全部集数；UGC（`BV`/`av`）→ 全部分 P（老项目只取
/// `pages[0]`，多 P 视频只能下到第一段，这里补全）；b23.tv 等分享短链先展开再解析。
class BiliDownloadService {
  BiliDownloadService({http.Client? linkClient})
      : _linkClient = linkClient ?? http.Client();

  final BiliBangumiService _bangumi = BiliBangumiService();
  final BiliVideoService _video = BiliVideoService();

  /// 短链展开专用 client（测试注入 MockClient，避免真实网络请求）。
  final http.Client _linkClient;

  /// 解析输入文本为 B 站引用：直接解析失败时展开 b23.tv 等分享短链再解析。
  ///
  /// 短链（如 `https://b23.tv/NkRjTgm`）本身不含 BV/av/ss/ep 令牌，须跟随
  /// 302 拿到真实 URL；命中令牌即停（不下载整页）。仍无法识别返回 null。
  Future<BiliBangumiRef?> resolveRef(String input) async {
    final ref = parseBiliBangumiUrl(input);
    if (ref != null) return ref;
    final expanded = await expandBiliShortLink(
      input,
      client: _linkClient,
      isTarget: (url) => parseBiliBangumiUrl(url) != null,
    );
    if (expanded == null) return null;
    return parseBiliBangumiUrl(expanded);
  }

  /// 解析链接为可下载目标。
  ///
  /// 支持：番剧（ss/ep）、用户视频（BV/av）、UP 主合集列表链接、b23.tv 短链；
  /// BV 属于某个合集时展开为整个合集（对齐 Bili23：`view` 接口返回的
  /// `ugc_season` 含全部章节+集+分P）。
  Future<BiliDownloadTarget> resolve(String input) async {
    final text = await _maybeExpand(input) ?? input;

    final ref = parseBiliBangumiUrl(text);
    if (ref != null) {
      return ref.isUgc ? _resolveUgc(ref) : _resolvePgc(ref);
    }

    final list = parseBiliSeasonListUrl(text);
    if (list != null) {
      return _resolveCollectionList(list);
    }

    throw const BiliApiException('无法识别 B 站链接（支持 BV / av / ss / ep / 合集链接 / b23.tv 短链）');
  }

  /// 若输入不是可直接识别的令牌/合集链接，则尝试展开 b23.tv 短链。
  Future<String?> _maybeExpand(String input) async {
    if (parseBiliBangumiUrl(input) != null ||
        parseBiliSeasonListUrl(input) != null) {
      return null;
    }
    return expandBiliShortLink(
      input,
      client: _linkClient,
      isTarget: (u) =>
          parseBiliBangumiUrl(u) != null || parseBiliSeasonListUrl(u) != null,
    );
  }

  /// 用户视频：属于合集则展开整个合集，否则展开分 P。
  Future<BiliDownloadTarget> _resolveUgc(BiliBangumiRef ref) async {
    final v = await _video.resolveUgcVideo(
      ref.bvid,
      aid: ref.aid > 0 ? ref.aid : null,
    );
    final season = v.ugcSeason;
    if (season != null && season.sections.isNotEmpty) {
      return _buildCollectionTarget(season);
    }
    final multi = v.pages.length > 1;
    final items = v.pages
        .map(
          (pg) => BiliDownloadItem(
            title: multi ? (pg.part.isNotEmpty ? pg.part : 'P${pg.page}') : v.title,
            aid: v.aid,
            cid: pg.cid,
            bvid: v.bvid,
          ),
        )
        .toList();
    if (items.isEmpty) {
      throw const BiliApiException('未解析到视频分 P');
    }
    return BiliDownloadTarget(
      title: v.title,
      cover: '',
      isBangumi: false,
      items: items,
    );
  }

  /// 番剧（PGC）：季详情全集数。
  Future<BiliDownloadTarget> _resolvePgc(BiliBangumiRef ref) async {
    final detail = await _bangumi.fetchSeasonDetail(
      seasonId: ref.hasSeason ? ref.seasonId : null,
      epId: ref.hasEpisode ? ref.epId : null,
    );
    final items = detail.episodes
        .map(
          (ep) => BiliDownloadItem(
            title: ep.longTitle.isNotEmpty ? ep.longTitle : ep.title,
            aid: ep.aid,
            cid: ep.cid,
            epId: ep.epId,
            seasonId: detail.seasonId,
            bvid: ep.bvid,
          ),
        )
        .toList();
    if (items.isEmpty) {
      throw const BiliApiException('该番剧没有可下载的集数');
    }
    return BiliDownloadTarget(
      title: detail.title,
      cover: detail.cover,
      isBangumi: true,
      items: items,
    );
  }

  /// 合集列表链接：取任一成员 bvid → view 接口拿全量 `ugc_season` → 展开。
  Future<BiliDownloadTarget> _resolveCollectionList(BiliSeasonListRef ref) async {
    final bvid =
        await _video.fetchFirstSeasonArchiveBvid(mid: ref.mid, seasonId: ref.seasonId);
    if (bvid == null || bvid.isEmpty) {
      throw const BiliApiException('该合集没有可下载的视频');
    }
    final v = await _video.resolveUgcVideo(bvid);
    final season = v.ugcSeason;
    if (season == null || season.sections.isEmpty) {
      throw const BiliApiException('该合集暂无内容');
    }
    return _buildCollectionTarget(season);
  }

  /// 把 `ugc_season` 展开为扁平下载条目（多章节时标题带章节前缀；多分P集展开到每 P）。
  BiliDownloadTarget _buildCollectionTarget(BiliUgcSeason season) {
    final multiSection = season.sections.length > 1;
    final items = <BiliDownloadItem>[];
    for (final section in season.sections) {
      final sectionTitle = section.title.trim();
      final prefix = multiSection && sectionTitle.isNotEmpty ? '[$sectionTitle] ' : '';
      for (final ep in section.episodes) {
        if (ep.pages.length > 1) {
          for (final pg in ep.pages) {
            items.add(BiliDownloadItem(
              title: '$prefix${pg.part.isNotEmpty ? pg.part : 'P${pg.page}'}',
              aid: ep.aid,
              cid: pg.cid,
              bvid: ep.bvid,
            ));
          }
        } else {
          items.add(BiliDownloadItem(
            title: '$prefix${ep.title.isNotEmpty ? ep.title : ep.bvid}',
            aid: ep.aid,
            cid: ep.cid,
            bvid: ep.bvid,
          ));
        }
      }
    }
    if (items.isEmpty) {
      throw const BiliApiException('该合集没有可下载的视频');
    }
    return BiliDownloadTarget(
      title: season.title,
      cover: season.cover,
      isBangumi: false,
      items: items,
    );
  }

  /// 拉取某个条目可选画质档（取第一条目的 playurl `accept_quality`）。
  Future<List<BiliQualityOption>> fetchQualityOptions(
    BiliDownloadTarget target,
  ) async {
    if (target.items.isEmpty) return const [];
    final first = target.items.first;
    final BiliPlayUrlResult result;
    if (target.isBangumi) {
      result = await _video.fetchPgcPlayUrl(
        epId: first.epId > 0 ? first.epId : null,
        seasonId: first.seasonId > 0 ? first.seasonId : null,
        cid: first.cid > 0 ? first.cid : null,
      );
    } else {
      result = await _video.fetchUgcPlayUrl(
        bvid: first.bvid.isEmpty ? null : first.bvid,
        avid: first.aid > 0 ? first.aid : null,
        cid: first.cid,
      );
    }
    return result.qualityOptions;
  }
}
