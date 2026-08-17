/// 自然序（数字感知）比较工具。
///
/// 名称排序使用：把字符串按「数字段 / 非数字段」切分后逐段比较，
/// 数字段按数值大小比较（而非逐字符），字母段大小写不敏感。
///
/// 例（升序）：`第2话 < 第12话 < 第112话`；`a1 < a2 < a10`。
library;

/// 自然序比较两个名称。[a] 小于 [b] 返回负值，相等返回 0，大于返回正值。
int naturalCompare(String a, String b) {
  final ta = _tokenize(a);
  final tb = _tokenize(b);
  final len = ta.length < tb.length ? ta.length : tb.length;
  for (var i = 0; i < len; i++) {
    final x = ta[i];
    final y = tb[i];
    final xNum = _isNumeric(x);
    final yNum = _isNumeric(y);
    if (xNum && yNum) {
      // 数字段按数值比较：先比长度（更长 = 数值更大），同长度再逐位比较
      final cmp = x.length == y.length
          ? x.compareTo(y)
          : x.length.compareTo(y.length);
      if (cmp != 0) return cmp;
    } else {
      final cmp = x.toLowerCase().compareTo(y.toLowerCase());
      if (cmp != 0) return cmp;
    }
  }
  // 公共前缀相同 → 更短的排在前面
  return ta.length.compareTo(tb.length);
}

/// 把字符串切成「数字段 / 非数字段」交替的 token 列表
List<String> _tokenize(String s) {
  if (s.isEmpty) return const [];
  final tokens = <String>[];
  final buffer = StringBuffer();
  var prevIsDigit = _isAsciiDigit(s.codeUnitAt(0));
  for (final code in s.codeUnits) {
    final isDigit = _isAsciiDigit(code);
    if (isDigit != prevIsDigit && buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
    prevIsDigit = isDigit;
    buffer.writeCharCode(code);
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());
  return tokens;
}

bool _isNumeric(String s) =>
    s.isNotEmpty && _isAsciiDigit(s.codeUnitAt(0));

bool _isAsciiDigit(int code) => code >= 0x30 && code <= 0x39;
