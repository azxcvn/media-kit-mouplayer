import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:moumou/services/download/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载管理器（ChangeNotifier 单例）：任务队列 + 并发槽调度 + 跨重启持久化。
///
/// 最多同时下载 [maxConcurrent] 个任务；`enqueue` 后自动 `_pump` 启动空闲槽，
/// 任务完成/失败后释放槽并启动下一个。暂停的任务保留占位，恢复后重新入队。
///
/// 持久化（工作.md 第 2 点）：任务列表（含状态/进度/产物路径）序列化到
/// SharedPreferences，重启后由 `ensureLoaded` 恢复，下载管理页不再「重启即清空」。
/// 重启前处于 pending/downloading/merging 的任务统一归位为 paused（不自动续跑）。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  /// 下载并发上限 = 1：视频串行下载（全选时按入队顺序一集一集下，避免并发触发
  /// 风控）；弹幕任务同样串行，但单条很小、几乎瞬时完成。
  static const int maxConcurrent = 1;

  static const String _key = 'bili_download_tasks';

  final List<DownloadTask> _tasks = [];
  final Set<DownloadTask> _running = {};

  /// 每个任务最近一次已持久化的状态（用于只在该状态变化时落盘）。
  final Map<String, DownloadStatus> _persistedStatus = {};

  Future<void>? _loadFuture;
  Future<void> _writeChain = Future.value();

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 加载去重（与其它设置单例同模式），main.dart 启动时调用。
  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final task = DownloadTask.fromJson(
          item is Map<String, dynamic> ? item : item.cast<String, dynamic>(),
        );
        if (task.id.isEmpty) continue;
        // 重启前未完成的任务（pending/downloading/merging）不自动续跑，
        // 归位为暂停，让用户在下载管理页手动继续。
        if (task.status == DownloadStatus.pending ||
            task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.merging) {
          task.markPausedForRestore();
        }
        _tasks.add(task);
        _attach(task);
        _persistedStatus[task.id] = task.status;
      }
      notifyListeners();
    } catch (_) {
      // 持久化数据损坏：静默忽略，不阻断启动
    }
  }

  void _attach(DownloadTask task) {
    task.addListener(notifyListeners);
    task.addListener(_onTaskChanged);
  }

  void _detach(DownloadTask task) {
    task.removeListener(notifyListeners);
    task.removeListener(_onTaskChanged);
  }

  /// 任务内部状态变化（进度/状态）时回调：仅当「状态」真正变化才落盘，
  /// 进度每 500ms 刷新一次，若每次都写盘会高频全量序列化（对齐进度服务节流思路）。
  void _onTaskChanged() {
    var changed = false;
    for (final t in _tasks) {
      if (_persistedStatus[t.id] != t.status) {
        _persistedStatus[t.id] = t.status;
        changed = true;
      }
    }
    if (changed) _persist();
  }

  void enqueue(DownloadTask task) {
    _attach(task);
    _tasks.add(task);
    _persistedStatus[task.id] = task.status;
    notifyListeners();
    _persist();
    _pump();
  }

  void pause(String id) {
    _taskById(id)?.pause();
    notifyListeners();
    _persist();
  }

  void resume(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.resume();
    notifyListeners();
    _persist();
    _pump();
  }

  void retry(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.resume();
    notifyListeners();
    _persist();
    _pump();
  }

  void remove(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.cancel();
    _detach(t);
    _tasks.remove(t);
    _running.remove(t);
    _persistedStatus.remove(id);
    notifyListeners();
    _persist();
  }

  /// 清除已完成/失败的任务。
  void clearFinished() {
    final removed = _tasks
        .where(
          (t) =>
              t.status == DownloadStatus.completed ||
              t.status == DownloadStatus.failed,
        )
        .toList();
    for (final t in removed) {
      _detach(t);
      _persistedStatus.remove(t.id);
    }
    _tasks.removeWhere(
      (t) =>
          t.status == DownloadStatus.completed ||
          t.status == DownloadStatus.failed,
    );
    notifyListeners();
    if (removed.isNotEmpty) _persist();
  }

  DownloadTask? _taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _pump() {
    for (final t in _tasks) {
      if (_running.length >= maxConcurrent) break;
      if (t.status == DownloadStatus.pending && !_running.contains(t)) {
        _running.add(t);
        t.run().whenComplete(() {
          _running.remove(t);
          notifyListeners();
          _pump();
        });
      }
    }
  }

  /// 全量序列化并串行写盘（快照在调用时同步生成，避免异步写乱序）。
  void _persist() {
    final snapshot = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    _writeChain = _writeChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, snapshot);
      } catch (_) {
        // 写盘失败不影响本次会话
      }
    });
  }

  /// 测试用：清空任务与加载标记（单例在测试间共享，避免状态泄漏）。
  @visibleForTesting
  void resetForTest() {
    for (final t in _tasks) {
      _detach(t);
    }
    _tasks.clear();
    _running.clear();
    _persistedStatus.clear();
    _loadFuture = null;
    _writeChain = Future.value();
  }
}
