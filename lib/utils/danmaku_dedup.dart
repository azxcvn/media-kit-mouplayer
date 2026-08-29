/// 弹幕去重纯函数（工作.md 弹幕第 4 点）：相同弹幕内容在时间窗口内
/// 合并为一条（对齐 Kazumi `mergeDuplicateDanmakus` 的归一化 + 时间窗
/// 合并语义；Kazumi 合并后显示「原文 xN」并置顶弹幕，本面板无发送场景，
/// 仅保留首条原文——去重的目的是刷屏合并，不改变呈现格式）。
///
/// 归一化（判同前先做，避免同义刷屏漏合并）：
/// - 转小写、全角转半角、全角空格转半角；
/// - 去所有空白（B站弹幕常见「6 6 6」与「666」刷屏）；
/// - 去标点符号（保留文字/数字/日文假名/韩文）；
/// - 连续相同字符收敛为 3 个（「66666」与「666」视为同一条）。
///
/// 纯函数、无 Flutter 依赖，可单测。
library;

import 'package:moumou/models/danmaku_entry.dart';

/// 默认合并时间窗（秒）：同内容弹幕 5 秒内只显示一条（Kazumi 同款）
const double kDanmakuDedupWindowSeconds = 5;

/// 内容归一化（判同键）
String normalizeDanmakuText(String raw) {
  final lower = raw.trim().toLowerCase();
  final buffer = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final code = lower.codeUnitAt(i);
    if (code == 0x3000) {
      // 全角空格 → 半角
      buffer.writeCharCode(0x20);
    } else if (code >= 0xFF01 && code <= 0xFF5E) {
      // 全角 ASCII → 半角
      buffer.writeCharCode(code - 0xFEE0);
    } else {
      buffer.writeCharCode(code);
    }
  }
  var text = buffer.toString();
  // 去空白（含普通空格/制表/换行）
  text = text.replaceAll(RegExp(r'\s+'), '');
  // 去标点（保留 \w / 中文 / 日文假名 / 日文与韩文区块）
  text = text.replaceAll(
    RegExp(
      r'[^\w\u4e00-\u9fff\u3040-\u309F\u30A0-\u30FF\u31F0-\u31FF\uFF65-\uFF9F]',
      unicode: true,
    ),
    '',
  );
  // 连续相同字符收敛为 3 个（66666 → 666）
  text = text.replaceAllMapped(RegExp(r'(.)\1{3,}'), (m) => m.group(1)! * 3);
  return text;
}

/// 时间窗去重：同归一化键的弹幕在 [windowSeconds] 内只保留首条。
///
/// 输入无需有序（按出现时间升序排序后处理）；输出保持时间升序。
List<DanmakuEntry> dedupeDanmakuEntries(
  List<DanmakuEntry> entries, {
  double windowSeconds = kDanmakuDedupWindowSeconds,
}) {
  if (entries.length < 2) return List.of(entries);
  final sorted = List.of(entries)
    ..sort((a, b) => a.time.compareTo(b.time));
  // 归一化键 → 该键上次保留弹幕的时间
  final lastKept = <String, double>{};
  final result = <DanmakuEntry>[];
  for (final entry in sorted) {
    final key = normalizeDanmakuText(entry.text);
    if (key.isEmpty) {
      // 归一化后为空（纯标点/空白弹幕）：不参与合并，原样保留
      result.add(entry);
      continue;
    }
    final last = lastKept[key];
    if (last != null && entry.time - last <= windowSeconds) {
      continue; // 窗口内重复 → 丢弃
    }
    lastKept[key] = entry.time;
    result.add(entry);
  }
  return result;
}
