/// B 站在线播放启动器：解析 playurl → 构造 [BiliMedia] → push [PlayerPage]。
///
/// 番剧详情、选集页、BV 链接解析三处入口复用，统一「解析中模态进度 →
/// 解析失败 toast → 成功进入播放页」的交互。
library;

import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/models/bili_media.dart';
import 'package:moumou/pages/player/player_page.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/bili_video_service.dart';

/// 播放 B 站 PGC 单集（番剧/影视）。
Future<void> playBiliEpisode(BuildContext context, BiliEpisode ep) async {
  final service = BiliVideoService();
  if (!context.mounted) return;
  _showLoading(context);
  try {
    final playUrl = await service.fetchPgcPlayUrl(epId: ep.epId, cid: ep.cid);
    if (!context.mounted) return;
    _dismissLoading(context);
    if (playUrl.defaultVideo == null || playUrl.defaultAudio == null) {
      _toast(context, '解析播放地址失败');
      return;
    }
    final media = _buildPgcMedia(service, ep, playUrl);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        path: playUrl.defaultVideo!.baseUrl,
        title: ep.longTitle.isNotEmpty ? ep.longTitle : ep.title,
        biliMedia: media,
      ),
    ));
  } catch (e) {
    if (context.mounted) {
      _dismissLoading(context);
      _toast(context, '播放失败：${_errText(e)}');
    }
  }
}

/// 播放 B 站 UGC（BV 号）。
Future<void> playBiliBvid(BuildContext context, String bvid) async {
  final service = BiliVideoService();
  if (!context.mounted) return;
  _showLoading(context);
  try {
    final video = await service.resolveUgcVideo(bvid);
    final playUrl = await service.fetchUgcPlayUrl(bvid: bvid, cid: video.cid);
    if (!context.mounted) return;
    _dismissLoading(context);
    if (playUrl.defaultVideo == null || playUrl.defaultAudio == null) {
      _toast(context, '解析播放地址失败');
      return;
    }
    final title = video.title.isEmpty ? bvid : video.title;
    final media = _buildUgcMedia(service, video, playUrl);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        path: playUrl.defaultVideo!.baseUrl,
        title: title,
        biliMedia: media,
      ),
    ));
  } catch (e) {
    if (context.mounted) {
      _dismissLoading(context);
      _toast(context, '播放失败：${_errText(e)}');
    }
  }
}

BiliMedia _buildPgcMedia(
  BiliVideoService service,
  BiliEpisode ep,
  BiliPlayUrlResult playUrl,
) {
  final title = ep.longTitle.isNotEmpty ? ep.longTitle : ep.title;
  return BiliMedia(
    epId: ep.epId,
    cid: ep.cid,
    aid: ep.aid,
    title: title,
    playUrl: playUrl,
    switchQuality: (qn) async => _buildPgcMedia(
      service,
      ep,
      await service.fetchPgcPlayUrl(epId: ep.epId, cid: ep.cid, qn: qn),
    ),
  );
}

BiliMedia _buildUgcMedia(
  BiliVideoService service,
  BiliUgcVideo video,
  BiliPlayUrlResult playUrl,
) {
  final title = video.title.isEmpty ? video.bvid : video.title;
  return BiliMedia(
    cid: video.cid,
    aid: video.aid,
    title: title,
    playUrl: playUrl,
    switchQuality: (qn) async => _buildUgcMedia(
      service,
      video,
      await service.fetchUgcPlayUrl(bvid: video.bvid, cid: video.cid, qn: qn),
    ),
  );
}

void _showLoading(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
}

void _dismissLoading(BuildContext context) {
  Navigator.of(context).pop();
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _errText(Object e) =>
    e is BiliApiException ? e.message : e.toString();
