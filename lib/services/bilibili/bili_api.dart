/// 哔哩哔哩端点常量（集中式，对齐 PiliPlus `http/api.dart` 的组织方式）。
///
/// 域名按登录域（passport）/ API 域（api）拆分；后续阶段在此追加端点。
library;

import 'package:moumou/services/bilibili/bili_constants.dart';

abstract final class BiliApi {
  // ── API 域（api.bilibili.com）────────────

  /// 设备指纹：取 buvid3/buvid4（响应 `data.b_3` / `data.b_4`）。
  static const String fingerSpi =
      '${BiliConstants.apiBaseUrl}/x/frontend/finger/spi';

  /// 登录态自检 + WBI 密钥来源（`data.wbi_img.img_url/sub_url`）。
  static const String nav = '${BiliConstants.apiBaseUrl}/x/web-interface/nav';

  /// 番剧索引筛选条件（`data.filter[]` / `data.order[]`，season_type + type）。
  static const String pgcIndexCondition =
      '${BiliConstants.apiBaseUrl}/pgc/season/index/condition';

  /// 番剧索引结果（分页列表，`data.list[]` + `data.has_next`）。
  static const String pgcIndexResult =
      '${BiliConstants.apiBaseUrl}/pgc/season/index/result';

  /// 番剧季详情（`result`：标题/封面/简介/episodes[]/seasons[] 多季切换）。
  static const String pgcSeasonDetail =
      '${BiliConstants.apiBaseUrl}/pgc/view/web/season';

  /// 番剧单集详情（ep_id 直达单集元数据）。
  static const String pgcEpisodeInfo =
      '${BiliConstants.apiBaseUrl}/pgc/season/episode/web/info';

  /// 新番时间表（`result[]`：按日期分组，含 episodes）。
  static const String pgcTimeline = '${BiliConstants.apiBaseUrl}/pgc/web/timeline';

  /// 分类搜索（`search_type=media_bangumi` 搜番剧，WBI 签名）。
  static const String searchByType =
      '${BiliConstants.apiBaseUrl}/x/web-interface/wbi/search/type';

  /// PGC 播放地址（v2，DASH 在 `result.video_info` 下；Cookie + WBI）。
  static const String pgcPlayUrl =
      '${BiliConstants.apiBaseUrl}/pgc/player/web/v2/playurl';

  /// UGC 播放地址（WBI 签名，DASH 在 `data` 下）。
  static const String ugcPlayUrl =
      '${BiliConstants.apiBaseUrl}/x/player/wbi/playurl';

  /// UGC 视频详情（bvid → cid/标题/分P，`data.pages[]`）。
  static const String ugcView =
      '${BiliConstants.apiBaseUrl}/x/web-interface/view';

  // ── 登录域（passport.bilibili.com）────────────

  /// 生成 TV 扫码二维码（android_hd 通道，appSign；返回 `data.auth_code` + `data.url`）。
  static const String tvQrAuthCode =
      '${BiliConstants.passBaseUrl}/x/passport-tv-login/qrcode/auth_code';

  /// 轮询 TV 扫码状态（顶层 `code` 为状态码，成功时 `data` 含 token_info + cookie_info）。
  static const String tvQrPoll =
      '${BiliConstants.passBaseUrl}/x/passport-tv-login/qrcode/poll';

  /// 退出登录（POST，需 csrf）。
  static const String logout = '${BiliConstants.passBaseUrl}/login/exit/v2';
}
