/// 哔哩哔哩视频解析服务：PGC/UGC playurl 请求 + DASH 选流 + bvid 解析。
///
/// - PGC：`/pgc/player/web/v2/playurl`，DASH 在 `result.video_info` 下；
/// - UGC：`/x/player/wbi/playurl`，DASH 在 `data` 下；
/// - 两者统一带 `fnval=4048`（DASH + flac + 杜比 + 4K/8K 位）、`fourk=1`，
///   并按 PiliPlus 惯例对参数做 WBI 签名（PGC 多签无害、UGC 必须）。
///
/// 画质默认请求最高档（qn=127），服务端按账户权限回落；`accept_quality` +
/// `accept_description` 供「更多 → 清晰度」列出可选档，切换档位时以目标 qn
/// 重新请求 playurl（重开播放器 + seek 保持进度）。
library;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_api.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/bili_fingerprint_utils.dart';
import 'package:moumou/utils/bili_wbi.dart';

class BiliVideoService {
  BiliVideoService({
    BiliHttp? http,
    Future<String> Function()? mixinKeyProvider,
  })  : _http = http ?? BiliAccount.instance.http,
        _mixinKeyProvider = mixinKeyProvider ?? _defaultMixinKey;

  final BiliHttp _http;
  final Future<String> Function() _mixinKeyProvider;

  static Future<String> _defaultMixinKey() => BiliAccount.instance.ensureMixinKey();

  /// 默认请求画质：1080P（无 1080P 时服务端按「最近可用档」回落）。
  static const int defaultQn = 80;

  /// PGC（番剧/影视）播放地址。
  Future<BiliPlayUrlResult> fetchPgcPlayUrl({
    int? epId,
    int? seasonId,
    int? cid,
    int qn = defaultQn,
    bool tryLook = false,
  }) async {
    final params = <String, Object>{
      if (epId != null && epId > 0) 'ep_id': epId,
      if (seasonId != null && seasonId > 0) 'season_id': seasonId,
      if (cid != null && cid > 0) 'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'web_location': 1315873, // 对齐 PiliPlus：web 客户端版本号，影响返回字段完整度
      ..._antiCrawlParams(),
      if (tryLook) 'try_look': 1,
    };
    final resp = await _getSigned(BiliApi.pgcPlayUrl, params);
    _ensureCode(resp);
    final result = _mapOf(resp['result']);
    final videoInfo = _mapOf(result['video_info']);
    final parsed = BiliPlayUrlResult.fromJson(videoInfo);
    debugPrint(
      '[BILI-VIDEO] pgc playurl: qn=$qn quality=${parsed.quality} '
      'videos=${parsed.videos.map((v) => v.id).join(',')} '
      'audio=${parsed.audios.map((a) => a.id).join(',')} '
      'clips=${parsed.clips.length} videoInfoKeys=${videoInfo.keys.join(',')}',
    );
    return parsed;
  }

  /// UGC（BV/av 普通视频）播放地址。
  Future<BiliPlayUrlResult> fetchUgcPlayUrl({
    String? bvid,
    int? avid,
    required int cid,
    int qn = defaultQn,
  }) async {
    final params = <String, Object>{
      if (bvid != null && bvid.isNotEmpty) 'bvid': bvid,
      if (avid != null && avid > 0) 'avid': avid,
      'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'web_location': 1315873,
      ..._antiCrawlParams(),
    };
    final resp = await _getSigned(BiliApi.ugcPlayUrl, params);
    _ensureCode(resp);
    return BiliPlayUrlResult.fromJson(_data(resp));
  }

  /// bvid（或 av 号）→ 视频标题 + 全部分 P（`/x/web-interface/view`）。
  ///
  /// 老链接只有 av 号时用 [aid] 走 aid 通道（工作.md 第 8 点）；BV 与 av 二选一，
  /// 两者都传时以 bvid 为准（服务端优先 bvid）。
  Future<BiliUgcVideo> resolveUgcVideo(String bvid, {int? aid}) async {
    final resp = await _http.getJson(
      BiliApi.ugcView,
      query: {
        if (bvid.isNotEmpty) 'bvid': bvid,
        if (bvid.isEmpty && aid != null && aid > 0) 'aid': '$aid',
      },
    );
    _ensureCode(resp);
    return BiliUgcVideo.fromJson(_data(resp));
  }

  /// 取 UP 主合集（`type=season`）第一个投稿的 bvid，用于后续借 view API 拿全量合集。
  /// 列表接口不含分 P 信息，此处仅取任一成员 bvid（`ugc_season` 本身含全量章节+集+分P）。
  Future<String?> fetchFirstSeasonArchiveBvid({
    required int mid,
    required int seasonId,
  }) async {
    final resp = await _http.getJson(
      BiliApi.seasonArchivesList,
      query: {
        'mid': '$mid',
        'season_id': '$seasonId',
        'sort_reverse': 'false',
        'page_size': '1',
        'page_num': '1',
        'web_location': '333.1387',
      },
    );
    _ensureCode(resp);
    final data = _data(resp);
    final archives = (data['archives'] as List?) ?? const [];
    if (archives.isEmpty) return null;
    final first = archives.first;
    return first is Map ? first['bvid'] as String? : null;
  }

  // ── 内部 ──────────────────────────────────────────────────────

  /// playurl 的 dm_img 反爬参数（对齐 PiliPlus：随机 dm_img_str 防 412 风控）。
  Map<String, Object> _antiCrawlParams() => {
        ...genDmImgParams(),
        'gaia_source': 'pre-load',
        'isGaiaAvoided': 'true',
      };

  /// 取 WBI 密钥并签名，返回完整 URL（`biliEncWbi` 就地改 params）。
  Future<Map<String, dynamic>> _getSigned(
    String url,
    Map<String, Object> params,
  ) async {
    final mixinKey = await _mixinKeyProvider();
    if (mixinKey.isEmpty) {
      throw const BiliApiException('未获取到 WBI 密钥，无法解析播放地址');
    }
    biliEncWbi(params, mixinKey);
    return _http.getJson('$url?${_wbiQuery(params)}');
  }

  String _wbiQuery(Map<String, Object> params) {
    final filter = RegExp(r"[!'()*]");
    final keys = params.keys.toList()..sort();
    return keys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(params[k].toString().replaceAll(filter, ''))}')
        .join('&');
  }

  Map<String, dynamic> _data(Map<String, dynamic> response) =>
      _mapOf(response['data']);

  Map<String, dynamic> _mapOf(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  void _ensureCode(Map<String, dynamic> response) {
    final code = (response['code'] as num?)?.toInt() ?? -1;
    if (code == 0) return;
    final message =
        (response['message'] ?? response['msg'])?.toString() ?? '';
    throw BiliApiException(_errorMessage(code, message));
  }

  /// 常见错误码 → 友好提示（合并 PiliPlus 与小喵两套）。
  String _errorMessage(int code, String message) {
    switch (code) {
      case -404:
        return '视频不存在或无权访问';
      case -403:
        return '无权访问，可能需要登录或大会员';
      case -10403:
        return '需要大会员权限';
      case -352:
        return '风控验证失败，请稍后重试';
      case 87008:
        return '专属视频，需开通相应权限';
      default:
        return message.isEmpty ? '服务器返回错误（code=$code）' : message;
    }
  }
}
