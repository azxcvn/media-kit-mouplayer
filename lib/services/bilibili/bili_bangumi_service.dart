import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_api.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/bili_wbi.dart';

/// 哔哩哔哩番剧（PGC）服务：索引筛选条件 / 分页结果 / 推荐 / 搜索 / 季详情 /
/// 新番时间表。请求参数对齐 PiliPlus `http/pgc.dart`：
/// - 索引：condition（`type=0`）→ result（`type=0` + `season_type` + 各筛选字段）；
/// - 推荐：固定 `order=3`（最常追番）+ 全 `-1` 筛选 + `type=1` + `pagesize=20`；
/// - 搜索：`/x/web-interface/wbi/search/type`（`search_type=media_bangumi`，WBI 签名）。
class BiliBangumiService {
  BiliBangumiService({
    BiliHttp? http,
    Future<String> Function()? mixinKeyProvider,
  })  : _http = http ?? BiliHttp(),
        _mixinKeyProvider = mixinKeyProvider ?? _defaultMixinKey;

  final BiliHttp _http;
  final Future<String> Function() _mixinKeyProvider;

  static Future<String> _defaultMixinKey() => BiliAccount.instance.ensureMixinKey();

  /// 索引筛选条件：GET /pgc/season/index/condition。
  Future<BiliIndexCondition> fetchCondition(int seasonType) async {
    final resp = await _http.getJson(BiliApi.pgcIndexCondition, query: {
      'season_type': '$seasonType',
      'type': '0',
    });
    return BiliIndexCondition.fromJson(_data(resp));
  }

  /// 索引分页结果（索引页用）：GET /pgc/season/index/result。
  ///
  /// [params] 为「字段 → 值」表（含 `order` 与各筛选维度，值 -1 表示不限），
  /// 由调用方按 condition 铺平后传入。
  Future<BiliIndexResult> fetchIndex({
    required int seasonType,
    required int page,
    Map<String, String> params = const {},
  }) async {
    final resp = await _http.getJson(BiliApi.pgcIndexResult, query: {
      'season_type': '$seasonType',
      'type': '0',
      'page': '$page',
      'pagesize': '21',
      ...params,
    });
    return BiliIndexResult.fromJson(_data(resp));
  }

  /// 番剧首页「推荐」网格：固定最常追番排序 + 全量不限筛选。
  Future<BiliIndexResult> fetchRecommend(int page) async {
    final resp = await _http.getJson(BiliApi.pgcIndexResult, query: {
      'st': '1',
      'order': '3',
      'season_version': '-1',
      'spoken_language_type': '-1',
      'area': '-1',
      'is_finish': '-1',
      'copyright': '-1',
      'season_status': '-1',
      'season_month': '-1',
      'year': '-1',
      'style_id': '-1',
      'sort': '0',
      'season_type': '1',
      'pagesize': '20',
      'type': '1',
      'page': '$page',
    });
    return BiliIndexResult.fromJson(_data(resp));
  }

  /// 番剧分类搜索：GET /x/web-interface/wbi/search/type（WBI 签名）。
  Future<BiliSearchResult> searchBangumi(String keyword, {int page = 1}) async {
    final mixinKey = await _mixinKeyProvider();
    if (mixinKey.isEmpty) {
      throw const BiliApiException('未获取到 WBI 密钥，无法搜索');
    }
    final params = <String, Object>{
      'search_type': 'media_bangumi',
      'keyword': keyword,
      'page': page,
      'page_size': 20,
      'platform': 'pc',
    };
    biliEncWbi(params, mixinKey);
    final resp = await _http.getJson('${BiliApi.searchByType}?${_wbiQuery(params)}');
    return BiliSearchResult.fromJson(_data(resp));
  }

  /// 季详情：GET /pgc/view/web/season（season_id 或 ep_id 二选一）。
  Future<BiliSeasonDetail> fetchSeasonDetail({int? seasonId, int? epId}) async {
    final resp = await _http.getJson(BiliApi.pgcSeasonDetail, query: {
      if (seasonId != null && seasonId > 0) 'season_id': '$seasonId',
      if (epId != null && epId > 0) 'ep_id': '$epId',
    });
    return BiliSeasonDetail.fromJson(_result(resp));
  }

  /// 新番时间表：GET /pgc/web/timeline（按日期分组）。
  Future<List<BiliTimelineDay>> fetchTimeline({
    int types = 1,
    int before = 6,
    int after = 6,
  }) async {
    final resp = await _http.getJson(BiliApi.pgcTimeline, query: {
      'types': '$types',
      'before': '$before',
      'after': '$after',
    });
    _ensureCode(resp);
    final result = resp['result'];
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((e) => BiliTimelineDay.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 追番时间表：番剧（types=1）+ 国创（types=4）两条时间线按日期合并。
  Future<List<BiliTimelineDay>> fetchTimelineMerged() async {
    final results = await Future.wait([
      fetchTimeline(types: 1),
      fetchTimeline(types: 4),
    ]);
    return _mergeTimeline(results[0], results[1]);
  }

  /// 按日期合并两条时间线（保序、同日 episodes 拼接）。
  List<BiliTimelineDay> _mergeTimeline(
    List<BiliTimelineDay> a,
    List<BiliTimelineDay> b,
  ) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final map = <String, BiliTimelineDay>{};
    final order = <String>[];
    for (final d in a) {
      map[d.date] = d;
      order.add(d.date);
    }
    for (final d in b) {
      final existing = map[d.date];
      if (existing != null) {
        map[d.date] = BiliTimelineDay(
          date: existing.date,
          dayOfWeek: existing.dayOfWeek,
          isToday: existing.isToday || d.isToday,
          episodes: [...existing.episodes, ...d.episodes],
        );
      } else {
        map[d.date] = d;
        order.add(d.date);
      }
    }
    return order.map((k) => map[k]!).toList();
  }

  /// WBI 签名后的查询串（与 `biliEncWbi` 使用同一套编码：键排序 +
  /// `Uri.encodeComponent` + 值剔除 `!'()*`）。
  String _wbiQuery(Map<String, Object> params) {
    final filter = RegExp(r"[!'()*]");
    final keys = params.keys.toList()..sort();
    return keys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(params[k].toString().replaceAll(filter, ''))}')
        .join('&');
  }

  /// 校验业务 `code`，通过则返回 `data`。
  Map<String, dynamic> _data(Map<String, dynamic> response) {
    _ensureCode(response);
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// 校验业务 `code`，通过则返回 `result`。
  Map<String, dynamic> _result(Map<String, dynamic> response) {
    _ensureCode(response);
    final result = response['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return result.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// 顶层 `code != 0` 抛 [BiliApiException]（message 优先）。
  void _ensureCode(Map<String, dynamic> response) {
    final code = (response['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final message = response['message'] as String? ?? '';
      throw BiliApiException(message.isEmpty ? '服务器返回错误（code=$code）' : message);
    }
  }
}
