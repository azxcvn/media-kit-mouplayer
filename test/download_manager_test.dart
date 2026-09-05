import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/services/download/download_manager.dart';
import 'package:moumou/services/download/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载记录持久化测试（工作.md 第 2 点：重启后下载记录不再被清空）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DownloadManager.instance.resetForTest();
  });

  DownloadTask videoTask({String id = 'vd_1'}) => DownloadTask(
        id: id,
        title: '第1话',
        subtitle: '某番剧',
        coverUrl: '',
        isVideo: true,
        saveDir: '/storage/emulated/0/Movies',
        aid: 1,
        cid: 100,
        epId: 200,
        seasonId: 300,
        bvid: 'BV1xx',
        qn: 80,
        withDanmaku: true,
      );

  test('DownloadTask toJson/fromJson 往返一致', () {
    final task = videoTask();
    final restored = DownloadTask.fromJson(task.toJson());
    expect(restored.id, task.id);
    expect(restored.title, task.title);
    expect(restored.subtitle, task.subtitle);
    expect(restored.isVideo, task.isVideo);
    expect(restored.saveDir, task.saveDir);
    expect(restored.aid, task.aid);
    expect(restored.cid, task.cid);
    expect(restored.epId, task.epId);
    expect(restored.seasonId, task.seasonId);
    expect(restored.bvid, task.bvid);
    expect(restored.qn, task.qn);
    expect(restored.withDanmaku, task.withDanmaku);
    expect(restored.status, DownloadStatus.pending);
  });

  test('重启恢复：未完成任务归位为暂停，已完成任务保留', () async {
    final completedJson = videoTask(id: 'vd_done').toJson()..['status'] = 'completed';
    final pendingJson = videoTask(id: 'vd_pending').toJson(); // status=pending

    SharedPreferences.setMockInitialValues({
      'bili_download_tasks': jsonEncode([completedJson, pendingJson]),
    });

    await DownloadManager.instance.ensureLoaded();
    final tasks = DownloadManager.instance.tasks;
    expect(tasks.length, 2);

    final done = tasks.firstWhere((t) => t.id == 'vd_done');
    expect(done.status, DownloadStatus.completed);

    final paused = tasks.firstWhere((t) => t.id == 'vd_pending');
    expect(paused.status, DownloadStatus.paused);
  });

  test('重启恢复：损坏数据静默忽略不崩溃', () async {
    SharedPreferences.setMockInitialValues({'bili_download_tasks': 'not-json'});
    await DownloadManager.instance.ensureLoaded();
    expect(DownloadManager.instance.tasks, isEmpty);
  });
}
