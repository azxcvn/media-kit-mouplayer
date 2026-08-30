/// 弹弹Play 弹幕评论 → 本地弹幕条目 / B站 XML 转换纯函数。
///
/// DanDanPlay 评论的 `p` 字段为 `"time,mode,color,userId"`（逗号串），
/// 与 B站 XML `<d p="time,mode,fontsize,color,...">` 的前三字段语义一致；
/// 转换后得到 [DanmakuEntry]，交给 [DanmakuController] 的调度器统一发射。
/// [dandanCommentsToXml] 把评论生成 B站 XML 文本，供网络弹幕**落盘持久化**
/// （重启播放/软件后经手动记忆恢复加载，与本地弹幕文件同一解析路径）。
/// 单条损坏跳过、结果按时间升序。
library;

import 'package:moumou/models/danmaku_entry.dart';
import 'package:moumou/models/dandan_models.dart';
import 'package:moumou/utils/danmaku_xml.dart';

/// 单条评论转弹幕条目；`p` 字段不足 / 时间非法 / 文本为空返回 null。
DanmakuEntry? dandanCommentToEntry(DandanComment comment) {
  final parts = comment.p.split(',');
  if (parts.length < 3) return null;
  final time = double.tryParse(parts[0]);
  if (time == null || time.isNegative || !time.isFinite) return null;
  final mode = int.tryParse(parts[1]) ?? 1;
  final color = int.tryParse(parts[2]) ?? 0xFFFFFF;
  final text = comment.m.trim();
  if (text.isEmpty) return null;
  return DanmakuEntry(
    time: time,
    mode: mode,
    color: color & 0xFFFFFF,
    text: text,
  );
}

/// 批量转换：逐条转换、丢弃损坏条目、按时间升序排序。
List<DanmakuEntry> dandanCommentsToEntries(List<DandanComment> comments) {
  final entries = <DanmakuEntry>[];
  for (final c in comments) {
    final e = dandanCommentToEntry(c);
    if (e != null) entries.add(e);
  }
  entries.sort((a, b) => a.time.compareTo(b.time));
  return entries;
}

/// 把弹弹Play 评论生成 B站 XML 文本（网络弹幕落盘持久化用）。
///
/// 与本应用 [parseDanmakuXml] 严格往返：损坏条目跳过规则与
/// [dandanCommentToEntry] 一致，`p` 末段保留弹幕 cid，`<source>` 标记来源。
String dandanCommentsToXml(List<DandanComment> comments) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<i>')
    ..writeln('  <chatserver>chat.bilibili.com</chatserver>')
    ..writeln('  <maxlimit>8000</maxlimit>')
    ..writeln('  <source>DanDanPlay</source>');
  for (final comment in comments) {
    final entry = dandanCommentToEntry(comment);
    if (entry == null) continue;
    buffer
      ..write(
        '  <d p="${entry.time},${entry.mode},25,${entry.color},0,0,0,${comment.cid}">',
      )
      ..write(escapeXmlText(entry.text))
      ..writeln('</d>');
  }
  buffer.write('</i>');
  return buffer.toString();
}
