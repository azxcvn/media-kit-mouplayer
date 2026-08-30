/// B站 XML 弹幕解析/生成纯函数（顶层函数，解析供 `compute` 放后台 isolate
/// 执行；生成用于网络弹幕落盘持久化）。
///
/// 解析格式：`<d p="time,mode,fontsize,color,ctime,pool,midHash,id">文本</d>`，
/// 对齐参考项目的 SAX 解析语义：单条损坏跳过、不打断整体；文本做 XML
/// 反转义（命名实体 + 十进制/十六进制数字实体）；结果按时间升序排序，
/// 保证同秒桶内的 stagger 错峰顺序稳定。
library;

import 'package:moumou/models/danmaku_entry.dart';

/// 解析 B站 XML 弹幕文本为条目列表。
///
/// 容错策略（单条损坏跳过）：`p` 属性缺失/字段不足/时间无法解析/文本为空
/// 的条目直接丢弃；格式完全不符（非弹幕 XML）返回空列表。
List<DanmakuEntry> parseDanmakuXml(String content) {
  final entries = <DanmakuEntry>[];
  // B站 XML 由工具生成、结构规整：`<d>` 文本内不会出现裸 `<`（会被转义），
  // 用受限正则提取即可；失败条目逐条跳过。
  final tagRegExp = RegExp(r'<d\b([^>]*)>(.*?)</d>', dotAll: true);
  final attrRegExp = RegExp(r'\bp="([^"]*)"');
  for (final match in tagRegExp.allMatches(content)) {
    final attrs = match.group(1) ?? '';
    final pMatch = attrRegExp.firstMatch(attrs);
    if (pMatch == null) continue;
    final fields = pMatch.group(1)!.split(',');
    if (fields.length < 4) continue; // 至少 time,mode,fontsize,color
    final time = double.tryParse(fields[0]);
    if (time == null || time.isNegative || !time.isFinite) continue;
    final mode = int.tryParse(fields[1]) ?? 1;
    final color = int.tryParse(fields[3]) ?? 0xFFFFFF;
    final text = unescapeXml(match.group(2) ?? '').trim();
    if (text.isEmpty) continue;
    entries.add(DanmakuEntry(
      time: time,
      mode: mode,
      color: color & 0xFFFFFF,
      text: text,
    ));
  }
  entries.sort((a, b) => a.time.compareTo(b.time));
  return entries;
}

/// XML 实体反转义（命名实体 + 数字实体，单趟替换）。
String unescapeXml(String input) {
  if (!input.contains('&')) return input;
  return input.replaceAllMapped(
    RegExp(r'&(amp|lt|gt|quot|apos|#x[0-9A-Fa-f]+|#\d+);'),
    (m) {
      final entity = m.group(1)!;
      switch (entity) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        default:
          final codePoint = entity.startsWith('#x')
              ? int.tryParse(entity.substring(2), radix: 16)
              : int.tryParse(entity.substring(1));
          if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) {
            return m.group(0)!; // 非法实体原样保留
          }
          return String.fromCharCode(codePoint);
      }
    },
  );
}

/// XML 文本转义（生成弹幕 XML 落盘用，与 [unescapeXml] 对称；
/// 顺序必须先转义 `&`，防止二次转义）。
String escapeXmlText(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
