/// WebDAV PROPFIND `multistatus` 响应的轻量解析（对齐 mpvRx 用 Sardine 解析
/// `DavResource` 的思路，但这里用手写容错解析，避免引入 XML 依赖）。
///
/// WebDAV 服务端命名空间前缀差异很大（`d:`/`D:`/无前缀），先做前缀剥离，
/// 再按 `<response>` 块提取 href / resourcetype / getcontentlength /
/// getlastmodified 等字段。
library;

import 'dart:convert';

/// 单个 WebDAV 资源（文件或目录）。
class WebDavResource {
  /// 解码后的路径（去掉百分号编码），以 `/` 开头。
  final String href;

  /// 资源末端段（文件名或目录名，不含尾部斜杠）。
  final String name;

  final bool isDirectory;

  /// 字节大小；未知为 -1（目录通常也为 -1，仅文件有意义）。
  final int contentLength;

  /// 最近修改时间（毫秒时间戳）；无法解析为 0。
  final int lastModifiedMs;

  const WebDavResource({
    required this.href,
    required this.name,
    required this.isDirectory,
    this.contentLength = -1,
    this.lastModifiedMs = 0,
  });
}

/// 解析 PROPFIND `multistatus` 响应体，返回全部资源（含目录的「自身」条目，
/// 由调用方按 href 过滤）。
List<WebDavResource> parseWebDavMultistatus(String xml) {
  final stripped = _stripNamespacePrefixes(xml);

  final resources = <WebDavResource>[];
  final responsePattern = RegExp(r'<response[^>]*>.*?</response>', dotAll: true);
  for (final m in responsePattern.allMatches(stripped)) {
    final block = m.group(0)!;

    final hrefText = _textOf(block, 'href');
    if (hrefText == null || hrefText.isEmpty) continue;

    final decodedHref = percentDecode(hrefText);
    final name = _lastSegment(decodedHref);
    if (name.isEmpty) continue;

    final isDirectory = block.contains('<collection');

    final sizeText = _textOf(block, 'getcontentlength');
    final size = (sizeText == null) ? -1 : (int.tryParse(sizeText.trim()) ?? -1);

    final modifiedText = _textOf(block, 'getlastmodified');
    final modifiedMs = (modifiedText == null)
        ? 0
        : parseHttpDate(modifiedText.trim());

    resources.add(
      WebDavResource(
        href: decodedHref,
        name: name,
        isDirectory: isDirectory,
        contentLength: size,
        lastModifiedMs: modifiedMs,
      ),
    );
  }
  return resources;
}

/// 去掉元素名上的命名空间前缀（`d:`, `D:`, `ns0:` 等），便于统一匹配。
String _stripNamespacePrefixes(String xml) {
  return xml.replaceAllMapped(
    RegExp(r'(</?)[A-Za-z_][A-Za-z0-9._-]*:'),
    (m) => m.group(1)!,
  );
}

/// 取第一个 `<tag>...</tag>` 的文本内容（忽略属性与可能的嵌套 CDATA）。
String? _textOf(String block, String tag) {
  final m = RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true).firstMatch(block);
  return m?.group(1);
}

/// 解码后的路径取末端段（去掉尾部斜杠再取最后一段）。
String _lastSegment(String decodedHref) {
  var p = decodedHref;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final idx = p.lastIndexOf('/');
  return idx < 0 ? p : p.substring(idx + 1);
}

/// 百分号解码（`%20` → 空格、`%E4%B8%AD` → `中`）。
///
/// 先把 `%xx` 与原始字符统一累积为 UTF-8 字节，再整体解码，避免多字节
/// 序列被逐字节拆成乱码。非法百分号序列（`%` 后非两位十六进制）原样保留。
String percentDecode(String input) {
  final bytes = <int>[];
  var i = 0;
  while (i < input.length) {
    final c = input.codeUnitAt(i);
    if (c == 0x25 /* % */ && i + 2 < input.length) {
      final hex = input.substring(i + 1, i + 3);
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        bytes.add(value);
        i += 3;
        continue;
      }
    }
    utf8.encode(String.fromCharCode(c)).forEach(bytes.add);
    i += 1;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

const _httpMonths = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// 解析 RFC 1123 格式的 HTTP 日期（`Sun, 06 Nov 1994 08:49:37 GMT`），
/// 返回毫秒时间戳；解析失败返回 0。
///
/// getlastmodified 标准即为此格式，忽略星期几与 `GMT` 后缀。
int parseHttpDate(String raw) {
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(raw);
  if (m == null) return 0;
  final day = int.tryParse(m.group(1)!);
  final month = _httpMonths[m.group(2)!];
  final year = int.tryParse(m.group(3)!);
  final hour = int.tryParse(m.group(4)!);
  final minute = int.tryParse(m.group(5)!);
  final second = int.tryParse(m.group(6)!);
  if (day == null || month == null || year == null || hour == null ||
      minute == null || second == null) {
    return 0;
  }
  return DateTime.utc(year, month, day, hour, minute, second)
      .millisecondsSinceEpoch;
}