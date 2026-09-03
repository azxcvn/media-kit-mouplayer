import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_constants.dart';
import 'package:moumou/services/bilibili/bili_danmaku_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/bili_video_service.dart';
import 'package:moumou/services/device_services.dart';
import 'package:path/path.dart' as p;

/// 下载任务状态。
enum DownloadStatus { pending, downloading, merging, paused, completed, failed }

/// 单个 B 站下载任务（视频 / 弹幕二选一）。
///
/// 视频任务：解析 playurl → 下载 video.m4s + audio.m4s → 原生 MediaMuxer 合并为
/// mp4（可选同步下载弹幕 XML）。弹幕任务：拉取分段弹幕 → 序列化 XML 落盘。
/// 复用 [BiliVideoService] / [BiliDanmakuService]（后者已用 varint 读 tag，规避
/// 老项目「多字节 tag 导致时间戳错乱」的坑）。
class DownloadTask extends ChangeNotifier {
  DownloadTask({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.isVideo,
    required this.saveDir,
    required this.aid,
    required this.cid,
    required this.epId,
    required this.seasonId,
    required this.bvid,
    required this.qn,
    required this.withDanmaku,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;

  /// true = 视频下载；false = 弹幕下载。
  final bool isVideo;
  final String saveDir;

  // B 站定位信息（视频：bvid/aid/cid 或 epId/seasonId；弹幕：aid/cid）。
  final int aid;
  final int cid;
  final int epId;
  final int seasonId;
  final String bvid;
  final int qn;
  final bool withDanmaku;

  DownloadStatus _status = DownloadStatus.pending;
  double _progress = 0; // 0~1
  double _speedBps = 0;
  String? _error;
  String? _outputPath;

  DownloadStatus get status => _status;
  double get progress => _progress;
  double get speedBps => _speedBps;
  String? get error => _error;

  /// 最终产物路径（mp4 / xml）。
  String? get outputPath => _outputPath;

  final BiliVideoService _video = BiliVideoService();
  final BiliDanmakuService _danmaku = BiliDanmakuService();

  bool _cancelled = false;
  bool _paused = false;

  int _lastBytes = 0;
  DateTime _lastSpeedAt = DateTime.now();

  /// 落盘文件名（去除路径非法字符后的标题）。
  String get _safeTitle => _sanitizeFileName(title);

  /// 下载是否被暂停（区别于取消/失败）。
  bool get isPaused => _status == DownloadStatus.paused;

  /// 请求取消（暂停 / 删除共用）；正在进行的流下载会在下一块到达时中止。
  void cancel() {
    _cancelled = true;
  }

  /// 暂停：标记并取消当前流下载，保留已写部分供 Range 续传。
  void pause() {
    _paused = true;
    _cancelled = true;
    if (_status == DownloadStatus.downloading) {
      _setStatus(DownloadStatus.paused);
    }
  }

  /// 恢复（由 [DownloadManager] 重新入队执行）。
  void resume() {
    _paused = false;
    _cancelled = false;
    _setStatus(DownloadStatus.pending);
  }

  /// 执行下载（幂等：已完成直接返回）。
  Future<void> run() async {
    if (_status == DownloadStatus.completed) return;
    _cancelled = false;
    _paused = false;
    try {
      if (isVideo) {
        await _runVideo();
      } else {
        await _runDanmaku();
      }
    } on _Cancelled {
      if (_paused) {
        _setStatus(DownloadStatus.paused);
      }
    } catch (e) {
      _setStatus(DownloadStatus.failed);
      _error = e is BiliApiException ? e.message : e.toString();
    }
  }

  // ── 弹幕下载 ──────────────────────────────────────────────

  Future<void> _runDanmaku() async {
    _setStatus(DownloadStatus.downloading);
    _setProgress(0);
    final entries = await _danmaku.fetchDanmaku(cid: cid, aid: aid);
    _ensureActive();
    if (entries.isEmpty) {
      throw const BiliApiException('该集没有弹幕');
    }
    final xml = danmakuEntriesToBiliXml(entries);
    final file = await _writeText('$_safeTitle.xml', xml);
    _outputPath = file.path;
    _setProgress(1);
    _setStatus(DownloadStatus.completed);
  }

  // ── 视频下载 ──────────────────────────────────────────────

  Future<void> _runVideo() async {
    _setStatus(DownloadStatus.downloading);
    _setProgress(0);

    final result = await _resolvePlayUrl();
    _ensureActive();
    final videoStream = result.defaultVideo;
    final audioStream = result.defaultAudio;
    if (videoStream == null) {
      throw const BiliApiException('未获取到视频流');
    }

    // 1) 可选：同步下载弹幕（先下，避免视频失败白下弹幕）
    if (withDanmaku) {
      await _downloadDanmakuSide();
    }

    // 2) 下载 video.m4s + audio.m4s
    final tmpVideo = File(p.join(saveDir, '$id.video.m4s'));
    final tmpAudio = File(p.join(saveDir, '$id.audio.m4s'));

    await _downloadToFile(videoStream.baseUrl, tmpVideo, start: 0.0, end: 0.5);
    if (audioStream != null && audioStream.baseUrl.isNotEmpty) {
      await _downloadToFile(audioStream.baseUrl, tmpAudio, start: 0.5, end: 1.0);
    }

    // 3) 合并
    _setStatus(DownloadStatus.merging);
    final output = File(p.join(saveDir, '$_safeTitle.mp4'));
    final hasAudio = audioStream != null && audioStream.baseUrl.isNotEmpty;
    final merged = hasAudio
        ? await DeviceServices.mergeM4s(tmpVideo.path, tmpAudio.path, output.path)
        : await tmpVideo.rename(output.path).then((_) => true);
    if (!merged) {
      throw const BiliApiException('音视频合并失败');
    }
    _outputPath = output.path;
    _setProgress(1);
    _setStatus(DownloadStatus.completed);
  }

  Future<void> _downloadDanmakuSide() async {
    try {
      final entries = await _danmaku.fetchDanmaku(cid: cid, aid: aid);
      if (entries.isNotEmpty) {
        await _writeText('$_safeTitle.xml', danmakuEntriesToBiliXml(entries));
      }
    } catch (_) {
      // 弹幕失败不影响视频下载
    }
  }

  Future<BiliPlayUrlResult> _resolvePlayUrl() async {
    if (epId > 0 || seasonId > 0) {
      return _video.fetchPgcPlayUrl(
        epId: epId > 0 ? epId : null,
        seasonId: seasonId > 0 ? seasonId : null,
        cid: cid > 0 ? cid : null,
        qn: qn,
      );
    }
    return _video.fetchUgcPlayUrl(
      bvid: bvid.isEmpty ? null : bvid,
      avid: aid > 0 ? aid : null,
      cid: cid,
      qn: qn,
    );
  }

  /// 流式下载 [url] 到 [file]；[start]/[end] 为本阶段在总进度中的占比。
  Future<void> _downloadToFile(
    String url,
    File file, {
    required double start,
    required double end,
  }) async {
    final client = http.Client();
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(_downloadHeaders());
    final existing = file.existsSync() ? file.lengthSync() : 0;
    final append = existing > 0;
    if (append) req.headers['Range'] = 'bytes=$existing-';

    final http.StreamedResponse resp;
    try {
      resp = await client.send(req);
    } catch (_) {
      client.close();
      throw const BiliApiException('网络请求失败');
    }
    // 416：Range 超出（文件已完整，可能是合并失败后的重试），直接跳过。
    if (resp.statusCode == 416) {
      client.close();
      return;
    }
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      client.close();
      throw BiliApiException('下载失败（HTTP ${resp.statusCode}）');
    }

    // 服务器忽略 Range（返回 200 而非 206）时不能续传，需从头重下。
    final resumeOk = append && resp.statusCode == 206;
    final startBytes = resumeOk ? existing : 0;
    final contentLen = resp.contentLength ?? -1;
    final total = startBytes + (contentLen > 0 ? contentLen : 0);
    var received = startBytes;
    final sink = file.openWrite(mode: resumeOk ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in resp.stream) {
        if (_cancelled) throw _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _setProgress(start + (end - start) * (received / total));
        }
        final now = DateTime.now();
        final dt = now.difference(_lastSpeedAt).inMilliseconds;
        if (dt >= 500) {
          _speedBps = (received - _lastBytes) * 1000.0 / dt;
          _lastBytes = received;
          _lastSpeedAt = now;
          notifyListeners();
        }
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      client.close();
      rethrow;
    }
    client.close();
  }

  Map<String, String> _downloadHeaders() => {
        'User-Agent': BiliConstants.webUserAgent,
        'Referer': BiliConstants.referer,
        if (BiliAccount.instance.cookieString.isNotEmpty)
          'Cookie': BiliAccount.instance.cookieString,
      };

  Future<File> _writeText(String name, String content) async {
    final file = File(p.join(saveDir, name));
    await file.writeAsString(content, flush: true);
    return file;
  }

  void _ensureActive() {
    if (_cancelled) throw _Cancelled();
  }

  void _setStatus(DownloadStatus s) {
    _status = s;
    notifyListeners();
  }

  void _setProgress(double v) {
    _progress = v.clamp(0.0, 1.0);
    notifyListeners();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

final RegExp _illegalFileChars = RegExp(r'[\\/:*?"<>|]');

/// 去除文件路径非法字符（B 站标题可能含 `/`、`:` 等），防止写盘失败。
String _sanitizeFileName(String name) {
  final trimmed = name.replaceAll(_illegalFileChars, '_').trim();
  if (trimmed.isEmpty) return '未命名';
  return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
}
