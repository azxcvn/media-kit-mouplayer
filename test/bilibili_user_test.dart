import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/bilibili_user.dart';

/// B 站用户信息模型测试（nav 接口 level_info / vip_label / money 解析）。
void main() {
  test('fromJson 解析等级/经验/会员/硬币', () {
    final user = BiliUser.fromJson({
      'isLogin': true,
      'mid': 123456,
      'uname': '测试用户',
      'face': 'https://example.com/face.jpg',
      'vipStatus': 2,
      'vipType': 2,
      'vip_label': {'text': '年度大会员', 'label_theme': 'annual_vip'},
      'level_info': {
        'current_level': 5,
        'current_min': 10800,
        'current_exp': 18800,
        'next_exp': 28800,
      },
      'money': 88.5,
    });

    expect(user.nickname, '测试用户');
    expect(user.level, 5);
    expect(user.currentExp, 18800);
    expect(user.nextExp, 28800);
    expect(user.money, 88.5);
    expect(user.levelLabel, 'LV5');
    expect(user.vipLabel, '年度大会员');
  });

  test('vipLabel 双字段判定：两者同时为真才判大会员', () {
    expect(
      BiliUser.fromJson({'vipStatus': 1, 'vipType': 1}).vipLabel,
      '大会员',
    );
    expect(
      BiliUser.fromJson({'vipStatus': 1, 'vipType': 2}).vipLabel,
      '年度大会员',
    );
    expect(
      BiliUser.fromJson({'vipStatus': 0, 'vipType': 0}).vipLabel,
      '普通会员',
    );
  });

  test('vipType 误报（TV 通道 vipType=1 但 vipStatus=0）判为普通会员', () {
    expect(
      BiliUser.fromJson({'vipStatus': 0, 'vipType': 1}).vipLabel,
      '普通会员',
    );
  });

  test('vipStatus 误报（vipStatus=1 但 vipType=0）判为普通会员', () {
    expect(
      BiliUser.fromJson({'vipStatus': 1, 'vipType': 0}).vipLabel,
      '普通会员',
    );
  });

  test('vipType=2 但 vipStatus 缺省(0) 也判为普通会员', () {
    expect(BiliUser.fromJson({'vipType': 2}).vipLabel, '普通会员');
  });

  test('满级(6)时 nextExp 缺省回退 currentExp', () {
    final user = BiliUser.fromJson({
      'level_info': {'current_level': 6, 'current_exp': 50000},
    });
    expect(user.level, 6);
    expect(user.nextExp, 50000);
  });

  test('guest 默认值', () {
    const g = BiliUser.guest();
    expect(g.isLogin, isFalse);
    expect(g.levelLabel, 'LV0');
    expect(g.vipLabel, '普通会员');
  });

  test('数字字段以字符串下发也能解析（登录 nav 自检崩溃修复）', () {
    final user = BiliUser.fromJson({
      'isLogin': true,
      'mid': '123456',
      'uname': '字符串字段用户',
      'vipStatus': '1',
      'vipType': '2',
      'vip_label': {'text': '年度大会员'},
      'level_info': {
        'current_level': '5',
        'current_exp': '18800',
        'next_exp': '28800',
      },
      'money': '88.5',
    });
    expect(user.mid, 123456);
    expect(user.level, 5);
    expect(user.currentExp, 18800);
    expect(user.nextExp, 28800);
    expect(user.money, 88.5);
    expect(user.vipLabel, '年度大会员');
  });

  test('isLogin 以 0/1 数字下发也能解析', () {
    expect(BiliUser.fromJson({'isLogin': 1}).isLogin, isTrue);
    expect(BiliUser.fromJson({'isLogin': 0}).isLogin, isFalse);
  });
}
