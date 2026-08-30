/// FTP 目录列表解析（对齐 mpvRx 用 Apache Commons Net `FTPFile` 的思路，
/// 这里为纯 Dart 手写解析，优先 RFC 3659 MLSD，LIST 作为兜底）。
library;

/// 一条 FTP 目录条目。
class FtpListEntry {
  final String name;
  final bool isDirectory;

  /// 字节大小；未知为 -1。
  final int size;

  /// 最近修改时间（毫秒时间戳）；无法解析为 0。
  final int lastModifiedMs;

  const FtpListEntry({
    required this.name,
    required this.isDirectory,
    this.size = -1,
    this.lastModifiedMs = 0,
  });
}

/// 解析单行 MLSD 输出：`type=file;size=123;modify=20160101000000; name.mp4`。
/// 返回 null 表示跳过该行（`.` / `..` / 空名 / 无法解析）。
FtpListEntry? parseMlsdLine(String line) {
  final stripped = line.replaceAll('\r', '').replaceAll('\n', '');
  final idx = stripped.indexOf(' ');
  if (idx < 0) return null;
  final facts = stripped.substring(0, idx);
  final name = stripped.substring(idx + 1).trim();
  if (name.isEmpty || name == '.' || name == '..') return null;

  var isDirectory = false;
  var size = -1;
  var modified = 0;
  for (final fact in facts.split(';')) {
    if (fact.isEmpty) continue;
    final eq = fact.indexOf('=');
    final key = eq < 0 ? fact : fact.substring(0, eq);
    final value = eq < 0 ? '' : fact.substring(eq + 1);
    switch (key.toLowerCase()) {
      case 'type':
        isDirectory = value.toLowerCase() == 'dir';
      case 'size':
        size = int.tryParse(value) ?? -1;
      case 'modify':
        modified = mlsdModifyToMs(value);
    }
  }
  return FtpListEntry(
    name: name,
    isDirectory: isDirectory,
    size: size,
    lastModifiedMs: modified,
  );
}

/// 解析 MLSD `modify` 事实值 `yyyyMMddHHmmss`（UTC）→ 毫秒时间戳，失败返回 0。
int mlsdModifyToMs(String value) {
  if (value.length != 14) return 0;
  int part(int start, int len) => int.tryParse(value.substring(start, start + len)) ?? -1;
  final year = part(0, 4);
  final month = part(4, 2);
  final day = part(6, 2);
  final hour = part(8, 2);
  final minute = part(10, 2);
  final second = part(12, 2);
  if ([year, month, day, hour, minute, second].any((v) => v < 0)) return 0;
  if (month < 1 || month > 12 || day < 1 || day > 31) return 0;
  return DateTime.utc(year, month, day, hour, minute, second)
      .millisecondsSinceEpoch;
}

/// 解析单行 Unix `LIST` 输出（`-rw-r--r-- ... 12345 Sep  1 10:00 name`）。
///
/// 注意：LIST 格式随服务器/平台差异很大（Windows、BSD、带年份等多种变体），
/// 本函数仅做最通用的 Unix 解析兜底；时间字段不解析（置 0），优先使用 MLSD。
/// 返回 null 表示无法识别该行。
FtpListEntry? parseUnixListLine(String line) {
  if (line.length < 10) return null;
  final first = line[0];
  if (first != 'd' && first != '-' && first != 'l') return null;

  final parts = line.trimRight().split(RegExp(r'\s+'));
  // 头 8 列：perms links owner group size mon day time/year；其后为文件名。
  if (parts.length < 9) return null;
  final name = parts.sublist(8).join(' ');
  if (name.isEmpty || name == '.' || name == '..') return null;

  return FtpListEntry(
    name: name,
    isDirectory: first == 'd',
    size: int.tryParse(parts[4]) ?? -1,
    lastModifiedMs: 0,
  );
}