/// HTTP Range 头解析（移植 mpvRx 的 HttpByteRange）。
///
/// 支持 `bytes=start-end`、`bytes=start-`、`bytes=-suffix` 三种形式；
/// 格式错误 / 多段 / 越界 / 不可满足时返回 null。
library;

class HttpByteRange {
  final int start;
  final int endInclusive;

  const HttpByteRange(this.start, this.endInclusive);

  int get length => endInclusive - start + 1;

  static final _syntax = RegExp(r'^bytes=(\d*)-(\d*)$', caseSensitive: false);

  static HttpByteRange? parse(String header, int completeLength) {
    if (completeLength <= 0) return null;
    final m = _syntax.firstMatch(header.trim());
    if (m == null) return null;
    final startText = m.group(1)!;
    final endText = m.group(2)!;
    if (startText.isEmpty && endText.isEmpty) return null;

    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      final start = (completeLength - suffixLength) < 0
          ? 0
          : completeLength - suffixLength;
      return HttpByteRange(start, completeLength - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start >= completeLength) return null;
    final requestedEnd = endText.isEmpty
        ? completeLength - 1
        : (int.tryParse(endText) ?? -1);
    if (requestedEnd < start) return null;
    return HttpByteRange(
        start, requestedEnd > completeLength - 1 ? completeLength - 1 : requestedEnd);
  }
}