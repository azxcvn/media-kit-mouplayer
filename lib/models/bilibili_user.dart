/// 哔哩哔哩用户信息模型（nav 接口 `data` 的纯数据映射）。
library;

/// 数字字段防崩：B 站部分接口把数字字段返回成字符串（对齐 `bili_bangumi.dart` 的约定），
/// 裸 `as num?` 强转会在字段为字符串时抛「String is not a subtype of num?」。
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

bool _asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

/// 已登录 B 站用户信息（昵称 / 头像 / 等级 / 经验 / 大会员状态 / 硬币）。
class BiliUser {
  final int mid;
  final String nickname;
  final String face;
  final bool isLogin;
  final int vipStatus; // 是否开通大会员：0 未开通 / 1 已开通
  final int vipType; // 大会员类型：0 无 / 1 月度大会员 / 2 年度及以上大会员
  final String vipLabelText; // 服务端 vip_label.text（如「大会员」）
  final int level; // 等级 0~6（6 为满级）
  final int currentExp; // 当前经验值
  final int nextExp; // 下一级所需经验值（满级时等于 currentExp）
  final double money; // 硬币

  const BiliUser({
    required this.mid,
    required this.nickname,
    required this.face,
    required this.isLogin,
    required this.vipStatus,
    this.vipType = 0,
    this.vipLabelText = '',
    this.level = 0,
    this.currentExp = 0,
    this.nextExp = 0,
    this.money = 0,
  });

  /// 游客（未登录）占位实例。
  const BiliUser.guest()
      : mid = 0,
        nickname = '',
        face = '',
        isLogin = false,
        vipStatus = 0,
        vipType = 0,
        vipLabelText = '',
        level = 0,
        currentExp = 0,
        nextExp = 0,
        money = 0;

  /// 会员状态文案（普通会员 / 大会员 / 年度大会员…）。
  ///
  /// 两个字段都会各自误报：TV 通道登录时 `vipType` 可能报 1（TV 大会员）而
  /// `vipStatus=0`；Web 通道登录时 `vipStatus` 可能误报 1 而 `vipType=0`。
  /// 因此**必须 `vipStatus==1` 且 `vipType>0` 同时成立**才判定为大会员，
  /// 任一为 0 都回落「普通会员」。文案优先用服务端 `vip_label.text`
  /// （覆盖「十年大会员」「百年大会员」等特殊档位）。
  String get vipLabel {
    final isVip = vipStatus > 0 && vipType > 0;
    if (!isVip) return '普通会员';
    if (vipLabelText.isNotEmpty) return vipLabelText;
    return vipType >= 2 ? '年度大会员' : '大会员';
  }

  /// 等级文案（如「LV5」）。
  String get levelLabel => 'LV$level';

  factory BiliUser.fromJson(Map<String, dynamic> json) {
    final levelInfo = json['level_info'];
    int level = 0;
    int currentExp = 0;
    int nextExp = 0;
    if (levelInfo is Map) {
      level = _asInt(levelInfo['current_level']);
      currentExp = _asInt(levelInfo['current_exp']);
      nextExp = _asInt(levelInfo['next_exp'], currentExp);
    }
    final vipLabel = json['vip_label'];
    final money = json['money'];
    return BiliUser(
      mid: _asInt(json['mid']),
      nickname: json['uname'] as String? ?? '',
      face: json['face'] as String? ?? '',
      isLogin: _asBool(json['isLogin']),
      vipStatus: _asInt(json['vipStatus']),
      vipType: _asInt(json['vipType']),
      vipLabelText:
          (vipLabel is Map && vipLabel['text'] is String) ? vipLabel['text'] as String : '',
      level: level,
      currentExp: currentExp,
      nextExp: nextExp,
      money: _asDouble(money),
    );
  }
}
