import 'package:flutter/foundation.dart';
import 'package:moumou/services/download/download_task.dart';

/// 下载管理器（ChangeNotifier 单例）：任务队列 + 并发槽调度。
///
/// 最多同时下载 [maxConcurrent] 个任务；`enqueue` 后自动 `_pump` 启动空闲槽，
/// 任务完成/失败后释放槽并启动下一个。暂停的任务保留占位，恢复后重新入队。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  /// 下载并发上限 = 1：视频串行下载（全选时按入队顺序一集一集下，避免并发触发
  /// 风控）；弹幕任务同样串行，但单条很小、几乎瞬时完成。
  static const int maxConcurrent = 1;

  final List<DownloadTask> _tasks = [];
  final Set<DownloadTask> _running = {};

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  void enqueue(DownloadTask task) {
    task.addListener(notifyListeners);
    _tasks.add(task);
    notifyListeners();
    _pump();
  }

  void pause(String id) {
    _taskById(id)?.pause();
    notifyListeners();
  }

  void resume(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.resume();
    notifyListeners();
    _pump();
  }

  void retry(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.resume();
    notifyListeners();
    _pump();
  }

  void remove(String id) {
    final t = _taskById(id);
    if (t == null) return;
    t.cancel();
    t.removeListener(notifyListeners);
    _tasks.remove(t);
    _running.remove(t);
    notifyListeners();
  }

  /// 清除已完成/失败的任务。
  void clearFinished() {
    _tasks.removeWhere(
      (t) =>
          t.status == DownloadStatus.completed ||
          t.status == DownloadStatus.failed,
    );
    notifyListeners();
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
}
