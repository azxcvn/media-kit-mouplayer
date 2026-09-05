import 'package:flutter/foundation.dart' show debugPrint;
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_api.dart';
import 'package:moumou/services/bilibili/bili_constants.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/bili_fingerprint_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 哔哩哔哩反爬设备指纹（完整版，对齐 Bili23-Downloader / PiliPlus）。
///
/// 负责生成 / 持久化 `_uuid`、`b_lsid`，拉取 `bili_ticket`，并激活 buvid3
/// （ExClimbWuzhi）；buvid3/buvid4 由 [BiliAccount] 预取后注入。最终拼出
/// 一段「设备指纹 Cookie 片段」供 [BiliHttp] 合并进每个请求的 `Cookie` 头。
///
/// 全部网络操作 best-effort（失败不阻断登录/请求），仅补全此前缺失的风控指纹，
/// 降低 playurl 等接口 412 风控概率。
class BiliFingerprint {
  BiliFingerprint({BiliHttp? http}) : _httpOverride = http;

  static final BiliFingerprint instance = BiliFingerprint._();
  BiliFingerprint._() : _httpOverride = null;

  final BiliHttp? _httpOverride;

  /// 懒加载：避免与 BiliAccount 的单例初始化产生循环引用
  /// （BiliAccount 持 BiliFingerprint.instance，此处首次用到时才取 BiliAccount.http）。
  late final BiliHttp _http = _httpOverride ?? BiliAccount.instance.http;

  Future<void>? _initFuture;

  /// 由 BiliAccount 在预取后注入。
  String buvid3 = '';
  String buvid4 = '';

  static const _keyUuid = 'bili_uuid';
  static const _keyBLsid = 'bili_blsid';
  static const _keyTicket = 'bili_ticket';
  static const _keyTicketExpires = 'bili_ticket_expires';

  String _uuid = '';
  String _bLsid = '';
  String _biliTicket = '';
  int _biliTicketExpires = 0;
  String _cookieFragment = '';

  /// 完整指纹 Cookie 片段（每次构建，含实时 b_nut）。
  String get cookieFragment => _cookieFragment;

  /// 初始化（幂等）：生成/读本地字段 → 拉 bili_ticket → 激活 buvid3 → 拼片段。
  Future<void> ensureInitialized() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _uuid = prefs.getString(_keyUuid) ?? '';
      _bLsid = prefs.getString(_keyBLsid) ?? '';
      _biliTicket = prefs.getString(_keyTicket) ?? '';
      _biliTicketExpires = prefs.getInt(_keyTicketExpires) ?? 0;

      if (_uuid.isEmpty) {
        _uuid = genBiliUuid();
        await prefs.setString(_keyUuid, _uuid);
      }
      if (_bLsid.isEmpty) {
        _bLsid = genBLsid();
        await prefs.setString(_keyBLsid, _bLsid);
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (_biliTicket.isEmpty || now >= _biliTicketExpires) {
        await _fetchTicket(prefs);
      }
      await _activateBuvid();
      _buildFragment();
    } catch (e) {
      // 指纹失败不阻断任何业务；仍尽力拼出本地片段
      debugPrint('[BILI-FP] init 失败: $e');
      _buildFragment();
    }
  }

  void _buildFragment() {
    final parts = <String>[
      if (_uuid.isNotEmpty) '_uuid=$_uuid',
      if (buvid3.isNotEmpty) 'buvid3=$buvid3',
      if (buvid4.isNotEmpty) 'buvid4=$buvid4',
      'b_nut=${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      if (_bLsid.isNotEmpty) 'b_lsid=$_bLsid',
      'buvid_fp=${genBuvidFp(BiliConstants.webUserAgent)}',
      if (_biliTicket.isNotEmpty) 'bili_ticket=$_biliTicket',
      if (_biliTicketExpires > 0) 'bili_ticket_expires=$_biliTicketExpires',
    ];
    _cookieFragment = parts.join('; ');
  }

  /// 拉取 web 端 bili_ticket（GenWebTicket，HMAC hexsign，有效期按 3 天计）。
  Future<void> _fetchTicket(SharedPreferences prefs) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final csrf = BiliAccount.instance.biliJct;
      final resp = await _http.postFormQuery(
        BiliApi.genWebTicket,
        query: {
          'key_id': 'ec02',
          'hexsign': biliTicketHexsign(ts),
          'context[ts]': '$ts',
          if (csrf.isNotEmpty) 'csrf': csrf,
        },
      );
      final code = (resp['code'] as num?)?.toInt() ?? -1;
      final data = resp['data'];
      if (code == 0 && data is Map) {
        final ticket = data['ticket'] as String? ?? '';
        if (ticket.isNotEmpty) {
          _biliTicket = ticket;
          _biliTicketExpires = ts + 3 * 24 * 3600;
          await prefs.setString(_keyTicket, ticket);
          await prefs.setInt(_keyTicketExpires, _biliTicketExpires);
        }
      } else {
        debugPrint('[BILI-FP] GenWebTicket code=$code');
      }
    } catch (e) {
      debugPrint('[BILI-FP] GenWebTicket 失败: $e');
    }
  }

  /// 激活 buvid3（ExClimbWuzhi），使本地 buvid 被风控体系认可。
  Future<void> _activateBuvid() async {
    if (buvid3.isEmpty) return;
    try {
      final resp = await _http.postJson(
        BiliApi.activateBuvid,
        body: genExClimbWuzhiPayload(),
      );
      final code = (resp['code'] as num?)?.toInt() ?? -1;
      if (code != 0) {
        debugPrint('[BILI-FP] ExClimbWuzhi code=$code');
      }
    } catch (e) {
      debugPrint('[BILI-FP] ExClimbWuzhi 失败: $e');
    }
  }

  /// 测试用：复位（单例在测试间共享）。
  void resetForTest() {
    _initFuture = null;
    buvid3 = '';
    buvid4 = '';
    _uuid = '';
    _bLsid = '';
    _biliTicket = '';
    _biliTicketExpires = 0;
    _cookieFragment = '';
  }
}
