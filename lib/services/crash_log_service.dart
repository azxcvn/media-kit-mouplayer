import 'package:flutter/services.dart';

/// 崩溃日志条目（来自原生 listCrashLogs）
class CrashLogFile {
  final String name;
  final String path;
  final int size;
  final int lastModified;

  const CrashLogFile({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
  });

  DateTime get modifiedAt => DateTime.fromMillisecondsSinceEpoch(lastModified);

  static CrashLogFile? fromMap(Map<String, dynamic> m) {
    final name = m['name'] as String?;
    final path = m['path'] as String?;
    if (name == null || path == null) return null;
    return CrashLogFile(
      name: name,
      path: path,
      size: (m['size'] as num?)?.toInt() ?? 0,
      lastModified: (m['lastModified'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 崩溃日志服务：原生 CrashHandler 自动把未捕获异常写入
/// `files/crash_logs/`（Android/data/包名/files/crash_logs/），
/// 本服务提供 列表 / 读取 / 删除 / 清空 / 导出（复制到公共 Download）。
class CrashLogService {
  CrashLogService._();

  static const MethodChannel _channel = MethodChannel('moumou/video_info');

  /// 日志保存目录（绝对路径，供错误日志页展示）
  static Future<String?> getLogDir() async {
    try {
      return await _channel.invokeMethod<String>('getCrashLogDir');
    } catch (_) {
      return null;
    }
  }

  /// 列出全部日志（按修改时间倒序）
  static Future<List<CrashLogFile>> listLogs() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listCrashLogs');
      if (raw == null) return const [];
      return raw
          .map((e) => CrashLogFile.fromMap(Map<String, dynamic>.from(e as Map)))
          .whereType<CrashLogFile>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 读取日志文件内容（UTF-8）
  static Future<String> readLog(String path) async {
    try {
      final content =
          await _channel.invokeMethod<String>('readCrashLog', {'path': path});
      return content ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 删除单个日志文件
  static Future<bool> deleteLog(String path) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('deleteCrashLog', {'path': path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 清空全部日志
  static Future<bool> clearLogs() async {
    try {
      final ok = await _channel.invokeMethod<bool>('clearCrashLogs');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 导出日志到公共 Download/moumou_logs/ 目录，返回新路径（失败 null）
  static Future<String?> exportLog(String path) async {
    try {
      return await _channel
          .invokeMethod<String>('exportCrashLog', {'path': path});
    } catch (_) {
      return null;
    }
  }

  /// 日志上限（risk_audit #8）：数量 ≤ [maxLogCount] 且总大小 ≤
  /// [maxLogBytes]，追加日志后超限自动删除最旧（防假崩溃/长期使用累积）。
  static const int maxLogCount = 50;
  static const int maxLogBytes = 10 * 1024 * 1024; // 10 MB

  /// Dart 侧未捕获异常 → 追加到崩溃日志目录（flutter_*.log）。
  /// 供 main() 的 FlutterError / Zone 钩子调用（失败静默，不影响运行）。
  /// 追加后顺带做一次自动裁剪（删除最旧日志，见 [_trimLogsIfNeeded]）。
  static Future<void> appendDartLog(String content) async {
    try {
      await _channel.invokeMethod<void>(
        'appendDartLog',
        {'content': content},
      );
    } catch (_) {
      // 静默：日志记录失败不阻塞应用
    }
    await _trimLogsIfNeeded();
  }

  /// 自动裁剪：日志数量/总大小超上限时删除最旧的。
  /// [listLogs] 已按修改时间倒序（最新在前），从尾部删最旧即可。
  static Future<void> _trimLogsIfNeeded() async {
    try {
      final logs = await listLogs();
      if (logs.isEmpty) return;
      var totalBytes = 0;
      for (final l in logs) {
        totalBytes += l.size;
      }
      while (logs.length > maxLogCount || totalBytes > maxLogBytes) {
        final oldest = logs.removeLast();
        totalBytes -= oldest.size;
        await deleteLog(oldest.path);
      }
    } catch (_) {
      // 静默：裁剪失败不影响运行
    }
  }
}
