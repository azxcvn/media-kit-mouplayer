import 'package:flutter/foundation.dart';
import 'package:moumou/models/bilibili_user.dart';
import 'package:moumou/services/bilibili/bili_auth_service.dart';
import 'package:moumou/services/bilibili/bili_credential_store.dart';
import 'package:moumou/services/bilibili/bili_fingerprint.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 哔哩哔哩账号状态（ChangeNotifier 单例）：登录态 / 用户信息 / WBI 密钥 /
/// buvid 设备指纹，并负责凭证的加密持久化与登录态自检。
///
/// - 启动 `ensureLoaded()`：读 buvid + 凭证，凭证有效则 nav 自检（过期静默清凭证）；
/// - 扫码登录：`startQrLogin`/`pollQr`/`completeQrLogin`；
/// - Cookie 导入：`importCookie`；
/// - 退出登录：`logout`（清凭证 + 回到游客态）。
class BiliAccount extends ChangeNotifier {
  static final BiliAccount instance = BiliAccount._();

  BiliAccount._();

  /// 加载去重（与其它设置单例同模式）
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() => _loadFuture ??= load();

  static const _keyBuvid3 = 'bili_buvid3';
  static const _keyBuvid4 = 'bili_buvid4';

  final BiliCredentialStore _credStore = BiliCredentialStore();
  final BiliHttp _http = BiliHttp();
  late final BiliAuthService auth = BiliAuthService(http: _http);
  final BiliFingerprint _fingerprint = BiliFingerprint.instance;

  BiliUser _user = const BiliUser.guest();
  BiliCredential? _credential;
  String _buvid3 = '';
  String _buvid4 = '';
  String _mixinKey = '';

  BiliUser get user => _user;
  bool get isLogin => _user.isLogin;
  String get buvid3 => _buvid3;
  String get mixinKey => _mixinKey;

  /// 共享请求实例（Cookie/buvid3 已注入）。视频/弹幕等需登录态的服务
  /// 未显式注入 [BiliHttp] 时默认复用此实例，避免「新建空实例不带登录
  /// Cookie → playurl 落回 480P、弹幕被降级」的问题。
  BiliHttp get http => _http;

  /// 当前登录 Cookie 串（未登录为空串），供测试/日志读取。
  String get cookieString => _credential?.cookieString ?? '';

  /// 当前登录的 bili_jct（csrf，未登录为空串）。
  String get biliJct => _credential?.biliJct ?? '';

  /// 当前登录凭证（测试/HTTP 层需要时读取）。
  @visibleForTesting
  BiliCredential? get credential => _credential;

  /// 启动加载：读 buvid 与凭证，凭证有效则 nav 自检。
  Future<void> load() async {
    try {
      await _loadBuvid();
      // 完整反爬指纹：注入 buvid → 生成/拉取本地字段 + bili_ticket + 激活 buvid3，
      // 再把指纹 Cookie 片段挂到共享 HTTP 实例（每个请求自动合并）。
      _fingerprint.buvid3 = _buvid3;
      _fingerprint.buvid4 = _buvid4;
      await _fingerprint.ensureInitialized();
      _http.extraCookies = _fingerprint.cookieFragment;
      final cred = await _credStore.read();
      if (cred.isValid) {
        _credential = cred;
        _http.cookie = cred.cookieString;
        final nav = await auth.nav();
        _user = nav.user;
        if (nav.mixinKey.isNotEmpty) _mixinKey = nav.mixinKey;
        if (!nav.user.isLogin) {
          // Cookie 过期（nav 静默降级）：清凭证回到游客态，引导重新扫码
          await _clearCredential();
        }
      }
    } catch (_) {
      // 网络失败 / 存储不可用：保留已读凭证（不误删），仅回游客态；下次操作再自检
      _user = const BiliUser.guest();
    }
    notifyListeners();
  }

  /// 生成 TV 扫码二维码（返回 url + auth_code）。
  Future<BiliQrCode> startQrLogin() async {
    await ensureLoaded();
    return auth.generateTvQr();
  }

  /// 轮询 TV 扫码状态。
  Future<BiliTvPoll> pollQr(String authCode) => auth.pollTvQr(authCode);

  /// 扫码成功后提取凭证并落盘 + 自检；返回确认后的用户信息。
  ///
  /// TV 登录凭证直接来自 poll 响应 JSON（cookie_info.cookies + token_info），
  /// 无 Set-Cookie / data.url 依赖。
  Future<BiliUser> completeQrLogin(BiliTvLoginData data) async {
    final cred = BiliCredential.fromCookies(
      data.cookies,
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
    );
    if (!cred.isValid) {
      throw const BiliApiException('登录凭证解析失败（缺少 SESSDATA）');
    }
    return _applyCredential(cred);
  }

  /// 浏览器 Cookie 导入（`SESSDATA=..; bili_jct=..; DedeUserID=..`）。
  Future<BiliUser> importCookie(String raw) async {
    final cred = BiliCredential.parse(raw);
    if (!cred.isValid) {
      throw const BiliApiException('Cookie 缺少 SESSDATA，无法登录');
    }
    return _applyCredential(cred);
  }

  /// 确保 WBI 密钥可用：已缓存直接返回，否则调 nav 取回（游客态 nav 也返回
  /// wbi_img）。失败返回空串（调用方据空串放弃签名请求）。
  Future<String> ensureMixinKey() async {
    if (_mixinKey.isNotEmpty) return _mixinKey;
    try {
      final nav = await auth.nav();
      if (nav.mixinKey.isNotEmpty) _mixinKey = nav.mixinKey;
    } on BiliApiException {
      // 静默：无密钥时调用方自行降级
    }
    return _mixinKey;
  }

  /// 刷新登录态（nav 自检）；网络失败不抛、保持现状。
  Future<void> refreshUser() async {
    try {
      final nav = await auth.nav();
      _user = nav.user;
      if (nav.mixinKey.isNotEmpty) _mixinKey = nav.mixinKey;
      if (!nav.user.isLogin && _credential != null) {
        await _clearCredential();
      }
      notifyListeners();
    } on BiliApiException {
      // 静默：下次操作再自检
    }
  }

  /// 退出登录：清凭证（尽力调用远端登出接口）+ 回游客态。
  Future<void> logout() async {
    final csrf = _credential?.biliJct ?? '';
    if (csrf.isNotEmpty) {
      try {
        await auth.logout(csrf);
      } catch (_) {
        // 远端登出失败不影响本地清凭证
      }
    }
    await _clearCredential();
    notifyListeners();
  }

  /// 落盘凭证 + nav 自检确认；凭证无效则抛异常并清空。
  Future<BiliUser> _applyCredential(BiliCredential cred) async {
    _credential = cred;
    _http.cookie = cred.cookieString;
    await _credStore.write(cred);
    final BiliNavData nav;
    try {
      nav = await auth.nav();
    } catch (e) {
      // 网络/业务失败：凭证已落盘但无法确认，回滚清空（避免「假登录」）
      await _clearCredential();
      notifyListeners();
      rethrow;
    }
    if (!nav.user.isLogin) {
      await _clearCredential();
      notifyListeners();
      throw const BiliApiException('登录失败：Cookie 无效或已过期');
    }
    _user = nav.user;
    if (nav.mixinKey.isNotEmpty) _mixinKey = nav.mixinKey;
    notifyListeners();
    return nav.user;
  }

  Future<void> _clearCredential() async {
    _credential = null;
    _http.cookie = null;
    _user = const BiliUser.guest();
    _mixinKey = '';
    await _credStore.clear();
  }

  Future<void> _loadBuvid() async {
    final prefs = await SharedPreferences.getInstance();
    var b3 = prefs.getString(_keyBuvid3);
    var b4 = prefs.getString(_keyBuvid4);
    if (b3 == null || b3.isEmpty) {
      try {
        final r = await auth.fetchBuvid();
        if (r.buvid3.isNotEmpty) {
          b3 = r.buvid3;
          await prefs.setString(_keyBuvid3, b3);
        }
        if (r.buvid4.isNotEmpty) {
          b4 = r.buvid4;
          await prefs.setString(_keyBuvid4, b4);
        }
      } catch (_) {
        // buvid 失败不阻断登录（仅影响后续 playurl 风控）
      }
    }
    _buvid3 = b3 ?? '';
    _buvid4 = b4 ?? '';
  }

  /// 测试用：恢复默认并清加载标记（单例在测试间共享，避免状态泄漏）。
  @visibleForTesting
  void resetForTest() {
    _loadFuture = null;
    _user = const BiliUser.guest();
    _credential = null;
    _buvid3 = '';
    _buvid4 = '';
    _mixinKey = '';
    _http.cookie = null;
    _http.extraCookies = null;
    _fingerprint.resetForTest();
  }
}
