/// 哔哩哔哩原声弹幕服务：分段 protobuf 获取 + 轻量解码 + 本地 XML 缓存。
///
/// 主路径对齐小喵 player 的 REST 分段接口（无需 gRPC、无需 WBI）：
/// - `GET /x/v2/dm/web/view?type=1&oid={cid}&pid={aid}` → `DmWebViewReply`，
///   取 `dmSge.total`（分段总数，每段 6 分钟）；
/// - `GET /x/v2/dm/web/seg.so?type=1&oid={cid}&pid={aid}&segment_index={n}`
///   → `DmSegMobileReply.elems`（`DanmakuElem[]`）。
/// 失败降级到 `comment.bilibili.com/{cid}.xml`（deflate 压缩的旧 XML）。
///
/// 解码用 `pb/pb_reader.dart` 手写 wire-format 读取（字段号对齐 PiliPlus
/// `v1.pb.dart`）；结果按 id 去重、按时间升序，转成本项目 [DanmakuEntry]。
/// 缓存落盘为标准 B 站 XML（`filesDir/danmaku/bilibili/{cid}.xml`），
/// 复用 `parseDanmakuXml` 读取——下载场景同名落盘后可自动进入本地弹幕链路。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_constants.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/services/bilibili/pb/pb_reader.dart';
import 'package:moumou/utils/danmaku_xml.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把 [DanmakuEntry] 列表序列化为标准 B 站 XML（与官方 `list.so` 同构，
/// 供本地缓存与下载场景复用；`p` 后 5 个字段填占位，渲染只用前 4 个）。
String danmakuEntriesToBiliXml(List<DanmakuEntry> entries) {
  final buf = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<i>\n');
  for (final e in entries) {
    buf
      ..write('  <d p="${e.time},${e.mode},25,${e.color},0,0,0,0">')
      ..write(escapeXmlText(e.text))
      ..write('</d>\n');
  }
  buf.write('</i>');
  return buf.toString();
}

/// 弹幕服务内部保留完整字段（id 用于跨分段去重；weight 暂不参与过滤）。
class _RawElem {
  final int id;
  final double time;
  final int mode;
  final int color;
  final String text;

  const _RawElem({
    required this.id,
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });

  DanmakuEntry toEntry() =>
      DanmakuEntry(time: time, mode: mode, color: color, text: text);
}

class BiliDanmakuService {
  BiliDanmakuService({BiliHttp? http}) : _http = http ?? BiliAccount.instance.http;

  final BiliHttp _http;

  static const String _viewUrl =
      '${BiliConstants.apiBaseUrl}/x/v2/dm/web/view';
  static const String _segUrl =
      '${BiliConstants.apiBaseUrl}/x/v2/dm/web/seg.so';
  static const String _legacyXmlHost = 'https://comment.bilibili.com';

  /// 测试用：覆盖缓存目录解析（单测环境无平台通道时注入临时目录）。
  @visibleForTesting
  static Future<Directory?> Function()? debugDirectoryOverride;

  /// 拉取完整弹幕（分段 protobuf 主路径；失败降级旧 XML；全失败返回空）。
  /// 不抛异常——调用方把空列表视为「无弹幕」，静默跳过。
  Future<List<DanmakuEntry>> fetchDanmaku({
    required int cid,
    int aid = 0,
  }) async {
    try {
      final entries = await _fetchProtobuf(cid: cid, aid: aid);
      if (entries.isNotEmpty) return entries;
    } catch (_) {
      debugPrint('[BILI-DANMAKU] danmaku cid=$cid: 分段 protobuf 异常，降级旧 XML',
          );
    }
    try {
      final entries = await _fetchLegacyXml(cid);
      debugPrint('[BILI-DANMAKU] danmaku cid=$cid: 旧 XML 降级结果 ${entries.length} 条',
          );
      return entries;
    } catch (_) {
      return const [];
    }
  }

  // ── 分段 protobuf 主路径 ──────────────────────────────────────

  Future<List<DanmakuEntry>> _fetchProtobuf({
    required int cid,
    required int aid,
    void Function(List<DanmakuEntry> batch)? onBatch,
  }) async {
    final pidParam = aid > 0 ? {'pid': '$aid'} : <String, String>{};
    final viewBytes = await _http.getBytes(_viewUrl, query: {
      'type': '1',
      'oid': '$cid',
      ...pidParam,
    });
    final total = _parseSegmentTotal(viewBytes);
    debugPrint('[BILI-DANMAKU] danmaku cid=$cid aid=$aid: 总分段数=$total',
        );
    if (total <= 0) return const [];

    final seen = <int>{};
    final raw = <_RawElem>[];
    // 分批并发（每批 3，对齐小喵限流，避免一次拉满触发风控）
    const batchSize = 3;
    for (var start = 1; start <= total; start += batchSize) {
      final end = start + batchSize - 1 > total ? total : start + batchSize - 1;
      final futures = <Future<List<_RawElem>>>[];
      for (var i = start; i <= end; i++) {
        futures.add(_fetchSegment(cid: cid, pid: aid, index: i));
      }
      final results = await Future.wait(futures);
      final batch = <_RawElem>[];
      for (final seg in results) {
        for (final e in seg) {
          if (seen.add(e.id)) batch.add(e);
        }
      }
      batch.sort((a, b) => a.time.compareTo(b.time));
      if (batch.isNotEmpty) {
        final entries = batch.map((e) => e.toEntry()).toList();
        raw.addAll(batch);
        onBatch?.call(entries);
      }
      debugPrint('[BILI-DANMAKU] danmaku cid=$cid: 分段 $start-$end 后共 ${raw.length} 条',
          );
    }
    raw.sort((a, b) => a.time.compareTo(b.time));
    debugPrint('[BILI-DANMAKU] danmaku cid=$cid: protobuf 结果共 ${raw.length} 条',
        );
    return raw.map((e) => e.toEntry()).toList();
  }

  /// 流式拉取弹幕：每完成一批（3 个分段）就回调一次 [onBatch]，先到先显
  /// （对齐 PiliPlus 的分段 feed）。返回累计条数；失败降级旧 XML（单批）。
  Future<int> fetchDanmakuStreamed({
    required int cid,
    int aid = 0,
    required void Function(List<DanmakuEntry> batch) onBatch,
  }) async {
    try {
      final entries =
          await _fetchProtobuf(cid: cid, aid: aid, onBatch: onBatch);
      if (entries.isNotEmpty) return entries.length;
    } catch (_) {
      debugPrint('[BILI-DANMAKU] danmaku cid=$cid: 分段 protobuf 异常，降级旧 XML',
          );
    }
    try {
      final entries = await _fetchLegacyXml(cid);
      onBatch(entries);
      debugPrint('[BILI-DANMAKU] danmaku cid=$cid: 旧 XML 降级结果 ${entries.length} 条',
          );
      return entries.length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<_RawElem>> _fetchSegment({
    required int cid,
    required int pid,
    required int index,
  }) async {
    try {
      final bytes = await _http.getBytes(_segUrl, query: {
        'type': '1',
        'oid': '$cid',
        if (pid > 0) 'pid': '$pid',
        'segment_index': '$index',
      });
      return _parseSegment(bytes);
    } catch (_) {
      // 单段失败不影响整体（其余分段照常返回；全空再走旧 XML 兜底）
      return const [];
    }
  }

  /// `DmWebViewReply.dmSge.total`（字段 4 → DmSegConfig 字段 2）。
  int _parseSegmentTotal(Uint8List bytes) {
    final reader = PbReader(bytes);
    for (final f in _fields(reader)) {
      if (f.fieldNumber == 4 && f.isLengthDelimited) {
        final cfg = PbReader(f.bytes);
        for (final cf in _fields(cfg)) {
          if (cf.fieldNumber == 2 && cf.isVarint) return cf.varint;
        }
      }
    }
    return 0;
  }

  /// `DmSegMobileReply`：字段 2 = state（1=弹幕关闭），字段 1 = elems。
  List<_RawElem> _parseSegment(Uint8List bytes) {
    final reader = PbReader(bytes);
    final elems = <_RawElem>[];
    for (final f in _fields(reader)) {
      if (f.fieldNumber == 2 && f.isVarint && f.varint == 1) {
        return const [];
      }
      if (f.fieldNumber == 1 && f.isLengthDelimited) {
        final e = _parseElem(f.bytes);
        if (e != null) elems.add(e);
      }
    }
    return elems;
  }

  /// `DanmakuElem`：字段 1=id、2=progress(ms)、3=mode、5=color、7=content。
  _RawElem? _parseElem(Uint8List bytes) {
    final reader = PbReader(bytes);
    var id = 0;
    var progressMs = 0;
    var mode = 1;
    var color = 0xFFFFFF;
    var content = '';
    for (final f in _fields(reader)) {
      if (f.fieldNumber == 1 && f.isVarint) {
        id = f.varint;
      } else if (f.fieldNumber == 2 && f.isVarint) {
        progressMs = f.varint;
      } else if (f.fieldNumber == 3 && f.isVarint) {
        mode = f.varint;
      } else if (f.fieldNumber == 5 && f.isVarint) {
        color = f.varint;
      } else if (f.fieldNumber == 7 && f.isLengthDelimited) {
        content = PbReader.bytesToString(f.bytes);
      }
    }
    final text = content.trim();
    if (text.isEmpty) return null;
    return _RawElem(
      id: id,
      time: progressMs / 1000.0,
      mode: mode,
      color: color & 0xFFFFFF,
      text: text,
    );
  }

  // ── 旧 XML 降级路径 ──────────────────────────────────────────

  Future<List<DanmakuEntry>> _fetchLegacyXml(int cid) async {
    final bytes = await _http.getBytes('$_legacyXmlHost/$cid.xml');
    final xml = _decodeXml(bytes);
    if (xml.isEmpty) return const [];
    return parseDanmakuXml(xml);
  }

  /// 旧 XML 接口是 deflate（raw）压缩；按 raw deflate → zlib → gzip →
  /// 纯文本的顺序兜底解码。
  String _decodeXml(Uint8List bytes) {
    try {
      return utf8.decode(ZLibDecoder(raw: true).convert(bytes));
    } catch (_) {}
    try {
      return utf8.decode(zlib.decode(bytes));
    } catch (_) {}
    try {
      return utf8.decode(gzip.decode(bytes));
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ── 本地 XML 缓存 ────────────────────────────────────────────

  /// 序列化并落盘到 `filesDir/danmaku/bilibili/{cid}.xml`，返回真实路径；
  /// 失败返回 null（不影响本次播放）。
  Future<String?> cacheDanmaku(int cid, List<DanmakuEntry> entries) async {
    if (entries.isEmpty) return null;
    final dir = await _danmakuDir();
    if (dir == null) return null;
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, '$cid.xml'));
      await file.writeAsString(danmakuEntriesToBiliXml(entries), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 读取本地缓存的弹幕；无缓存或解析失败返回 null。
  Future<List<DanmakuEntry>?> loadCachedDanmaku(int cid) async {
    final dir = await _danmakuDir();
    if (dir == null) return null;
    final file = File(p.join(dir.path, '$cid.xml'));
    if (!await file.exists()) return null;
    try {
      final entries = parseDanmakuXml(await file.readAsString());
      return entries.isEmpty ? null : entries;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _danmakuDir() async {
    final override = debugDirectoryOverride;
    if (override != null) return override();
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'danmaku', 'bilibili'));
    } catch (_) {
      return null;
    }
  }

  Iterable<PbField> _fields(PbReader reader) sync* {
    while (reader.hasNext) {
      final f = reader.readField();
      if (f == null) break;
      yield f;
    }
  }
}
