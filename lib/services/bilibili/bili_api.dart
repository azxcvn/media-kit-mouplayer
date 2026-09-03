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
