/// 在线播放 B 站媒体的值对象：当前画质的 DASH 流 + 弹幕/章节元数据 +
/// 画质切换回调。
///
/// 由入口页（番剧详情 / 选集 / BV 解析）先解析 playurl 后构造，传给
/// [PlayerPage] 驱动：双流播放（video + 外挂 audio）、B 站原声弹幕、
/// OP/ED 章节跳段与「更多 → 清晰度」切换。
library;

import 'package:moumou/models/bili_dash.dart';

class BiliMedia {
  final int? epId;
  final int? seasonId;

  /// 弹幕 oid（也作为进度/缓存键）。
  final int cid;

  /// 弹幕 pid（= aid）；PGC 拿不到时填 0。
  final int aid;

  final String title;

  /// 当前画质对应的 DASH 解析结果。
  final BiliPlayUrlResult playUrl;

  /// 按目标 qn 重新解析 playurl 并返回新的 [BiliMedia]（元数据不变）。
  final Future<BiliMedia> Function(int qn) switchQuality;

  const BiliMedia({
    this.epId,
    this.seasonId,
    required this.cid,
    this.aid = 0,
    required this.title,
    required this.playUrl,
    required this.switchQuality,
  });

  /// 当前画质视频流 URL（无可用流时为空串）。
  String get videoUrl => playUrl.defaultVideo?.baseUrl ?? '';

  /// 当前画质音频流 URL（无音轨时 null）。
  String? get audioUrl => playUrl.defaultAudio?.baseUrl;

  /// 可选画质档（「更多 → 清晰度」面板展示）。
  List<BiliQualityOption> get qualities => playUrl.qualityOptions;

  /// 当前画质 qn。
  int get currentQn => playUrl.quality;

  /// OP/ED 跳段信息（来自 playurl 的 `clip_info_list`）。
  List<BiliClipInfo> get clips => playUrl.clips;
}
