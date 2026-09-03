/// 哔哩哔哩用户信息模型（nav 接口 `data` 的纯数据映射）。
library;

/// 已登录 B 站用户信息（昵称 / 头像 / 等级 / 经验 / 大会员状态 / 硬币）。
class BiliUser {
  final int mid;
  final String nickname;
  final String face;
  final bool isLogin;
  final int vipStatus; // 0 非会员 / 1 大会员 / 2 年度大会员
  final int vipType; // 0 无 / 1 月度大会员 / 2 年度及以上大会员
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
  /// 以 `vipType`（会员类型：0 无 / 1 月度大会员 / 2 年度及以上大会员）为权威依据；
  /// `vipStatus`（是否开通）对非大会员用户可能误报，不作为判定。文案优先用服务端
  /// `vip_label.text`（覆盖「十年大会员」「百年大会员」等特殊档位）。
  String get vipLabel {
    if (vipType == 0) return '普通会员';
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
      level = (levelInfo['current_level'] as num?)?.toInt() ?? 0;
      currentExp = (levelInfo['current_exp'] as num?)?.toInt() ?? 0;
      nextExp = (levelInfo['next_exp'] as num?)?.toInt() ?? currentExp;
    }
    final vipLabel = json['vip_label'];
    final money = json['money'];
    return BiliUser(
      mid: (json['mid'] as num?)?.toInt() ?? 0,
      nickname: json['uname'] as String? ?? '',
      face: json['face'] as String? ?? '',
      isLogin: json['isLogin'] as bool? ?? false,
      vipStatus: (json['vipStatus'] as num?)?.toInt() ?? 0,
      vipType: (json['vipType'] as num?)?.toInt() ?? 0,
      vipLabelText:
          (vipLabel is Map && vipLabel['text'] is String) ? vipLabel['text'] as String : '',
      level: level,
      currentExp: currentExp,
      nextExp: nextExp,
      money: money is num ? money.toDouble() : 0,
    );
  }
}
