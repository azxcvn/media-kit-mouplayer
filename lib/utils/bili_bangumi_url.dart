/// 哔哩哔哩番剧链接解析纯函数：从用户粘贴的 URL/文本中提取 season_id / ep_id /
/// BV 号三种令牌，供「输入链接解析 → 详情页」入口使用。
///
/// 覆盖 `bangumi/play/ss12345`、`bangumi/play/ep123456`、`video/BVxxxx` 三类；
/// UGC（BV）播放属阶段三，这里只负责识别出类型，由调用方决定提示。
library;

final RegExp _reBv = RegExp(r'BV[0-9A-Za-z]{10}');
final RegExp _reEp = RegExp(r'[eE][pP](\d+)');
final RegExp _reSs = RegExp(r'[sS][sS](\d+)');

/// 解析出的番剧引用（season / episode / UGC 三选一，其余为 0/空）。
class BiliBangumiRef {
  final int seasonId;
  final int epId;
  final String bvid;

  const BiliBangumiRef({this.seasonId = 0, this.epId = 0, this.bvid = ''});

  bool get hasSeason => seasonId > 0;
  bool get hasEpisode => epId > 0;
  bool get isUgc => bvid.isNotEmpty;

  /// 是否识别出任何可解析的令牌。
  bool get isValid => hasSeason || hasEpisode || isUgc;
}

/// 解析链接文本；未识别到任何令牌返回 null。
BiliBangumiRef? parseBiliBangumiUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // 优先 season_id（番剧季详情是阶段二入口页）
  final ss = _reSs.firstMatch(text);
  if (ss != null) {
    return BiliBangumiRef(seasonId: int.parse(ss.group(1)!));
  }

  final ep = _reEp.firstMatch(text);
  if (ep != null) {
    return BiliBangumiRef(epId: int.parse(ep.group(1)!));
  }

  final bv = _reBv.firstMatch(text);
  if (bv != null) {
    return BiliBangumiRef(bvid: bv.group(0)!);
  }

  return null;
}
