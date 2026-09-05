/// 哔哩哔哩协议常量：域名 / 请求头 / TV appkey·appsec / 扫码状态码。
///
/// 只放「跨文件共享的常量」；WBI 签名的混淆表与纯函数放 `utils/bili_wbi.dart`
/// （可单测）。域名对齐 PiliPlus `http/constants.dart`。
library;

abstract final class BiliConstants {
  /// 主 API 域（nav / playurl / 番剧索引 / 弹幕等 Web 接口）。
  static const String apiBaseUrl = 'https://api.bilibili.com';

  /// 登录域（扫码 / 短信 / 密码 / TV）。
  static const String passBaseUrl = 'https://passport.bilibili.com';

  /// APP 域（TV 接口，后续 TV 通道用）。
  static const String appBaseUrl = 'https://app.bilibili.com';

  /// 请求 CDN 直链与部分 Web 接口时必须携带的 Referer（对齐小喵 player 经验）。
  static const String referer = 'https://www.bilibili.com';

  /// Web 通道统一浏览器 UA（全程一致，风控要求）。
  static const String webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// TV 端 appkey / appsec（PiliPlus 公开常量；登录已改 Web 扫码，此常量保留供
  /// 后续 tv playurl 参考，属灰色地带，默认不启用）。
  static const String tvAppKey = 'dfca71928277209b';
  static const String tvAppSec = 'b5475a8825547a4fc26c7d518eaaa02e';

  /// TV 通道（android_hd）接口用的 BiliDroid UA 与固定 traceId（对齐 PiliPlus，供 tv playurl 参考）。
  static const String tvUserAgent =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd '
      'mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2';
  static const String tvTraceId =
      '11111111111111111111111111111111:1111111111111111:0:0';

  /// TV 扫码轮询状态码（poll 响应顶层 `code`）。
  static const int qrNotScanned = 86101; // 未扫码
  static const int qrScanned = 86090; // 已扫码未确认
  static const int qrExpired = 86038; // 二维码已失效（约 180 秒）
  static const int qrSuccess = 0; // 登录成功
}
