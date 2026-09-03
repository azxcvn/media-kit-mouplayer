import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/bili_video_service.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';

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
/// 番剧（`ss`/`ep`）→ 季详情全部集数；UGC（`BV`）→ 全部分 P（老项目只取
/// `pages[0]`，多 P 视频只能下到第一段，这里补全）。
class BiliDownloadService {
  final BiliBangumiService _bangumi = BiliBangumiService();
  final BiliVideoService _video = BiliVideoService();

  Future<BiliDownloadTarget> resolve(String input) async {
    final ref = parseBiliBangumiUrl(input);
    if (ref == null) {
      throw const BiliApiException('无法识别 B 站链接（支持 BV / ss / ep）');
    }

    if (ref.isUgc) {
      final v = await _video.resolveUgcVideo(ref.bvid);
      final multi = v.pages.length > 1;
      final items = v.pages
          .map(
            (pg) => BiliDownloadItem(
              title: multi
                  ? (pg.part.isNotEmpty ? pg.part : 'P${pg.page}')
                  : v.title,
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
