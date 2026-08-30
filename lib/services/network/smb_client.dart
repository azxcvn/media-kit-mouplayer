/// SMB 客户端：纯 Dart 实现（基于 `smb_connect` 包），替代此前的 jcifs-ng 原生桥接。
///
/// 路径约定（对齐其余协议的 `NetworkPath` 语义）：`/` 表示服务器根（列共享），
/// `/share/...` 的第一段为共享名。`openRead(file, start, end)` 原生支持 offset 分段读取。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';
import 'package:moumou/models/network_connection.dart';
import 'package:moumou/models/network_file.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/utils/network_mime_types.dart';

class SmbClient implements NetworkClient {
  final NetworkConnection connection;

  SmbClient(this.connection);

  SmbConnect? _connect;

  @override
  bool isConnected() => _connect != null;

  @override
  Future<void> connect() async {
    await disconnect();
    try {
      final c = await SmbConnect.connectAuth(
        host: connection.host,
        username: connection.isAnonymous ? '' : connection.username,
        password: connection.isAnonymous ? '' : connection.password,
        domain: '',
      );
      _connect = c;
    } catch (e) {
      throw NetworkClientException(_friendly(e));
    }
  }

  @override
  Future<void> disconnect() async {
    final c = _connect;
    _connect = null;
    if (c == null) return;
    try {
      await c.close();
    } catch (_) {
      // 幂等断开，忽略异常
    }
  }

  @override
  Future<List<NetworkFile>> listFiles(String path) async {
    final c = _requireConnect();
    try {
      if (path == '/' || path.isEmpty) {
        final shares = await c.listShares();
        return [
          for (final f in shares)
            // 过滤管理/隐藏共享：ADMIN$、C$、D$、IPC$ 等以 $ 结尾，只保留普通共享。
            if (!f.name.endsWith(r'$'))
              NetworkFile(name: f.name, path: f.path, isDirectory: true),
        ];
      }
      final folder = await c.file(path);
      final files = await c.listFiles(folder);
      return files.map(_toFile).toList();
    } catch (e) {
      throw NetworkClientException(_friendly(e));
    }
  }

  @override
  Future<int> getFileSize(String path) async {
    final c = _requireConnect();
    try {
      final f = await c.file(path);
      return f.size;
    } catch (e) {
      print('[SMB] getFileSize($path) 失败: $e');
      return -1;
    }
  }

  @override
  Future<Stream<List<int>>> openStream(String path, {int offset = 0}) async {
    final c = _requireConnect();
    try {
      final f = await c.file(path);
      if (f.size > 0) {
        return _pipelinedStream(c, f, f.size, offset);
      }
      return await c.openRead(f, offset);
    } catch (e) {
      print('[SMB] openStream($path, $offset) 失败: $e');
      throw NetworkClientException(_friendly(e));
    }
  }

  /// 并发预读管线：用多个独立文件句柄并发读取、按序输出。
  ///
  /// smb_connect 底层读取是“发一个 64KB 读请求 → 等响应 → 再发下一个”，全串行，
  /// 吞吐上限被压在 64KB ÷ 往返延迟。配合 fork 库里移除的全局锁，这里用 [workers]
  /// 个句柄各自读不同块并按块序号合并，让多个读请求同时在途，吞吐随并发数提升。
  Stream<List<int>> _pipelinedStream(SmbConnect c, SmbFile f, int size, int offset) {
    const workers = 4;
    const block = 64000; // 略小于底层单次 SMB2 读上限(64936)，保证一次往返读满一块
    final total = size - offset;
    final totalBlocks = total <= 0 ? 0 : (total + block - 1) ~/ block;

    final controller = StreamController<List<int>>();
    final completed = <int, List<int>>{};
    var nextToYield = 0;
    var failed = false;

    void deliver() {
      if (controller.isClosed) return;
      while (completed.containsKey(nextToYield)) {
        controller.add(completed.remove(nextToYield)!);
        nextToYield++;
      }
      if (nextToYield >= totalBlocks) {
        controller.close();
      }
    }

    Future<void> worker(int seed) async {
      RandomAccessFile? raf;
      try {
        raf = await c.open(f, mode: FileMode.read);
        for (var i = seed; i < totalBlocks; i += workers) {
          final start = offset + i * block;
          final want = (i == totalBlocks - 1) ? total - i * block : block;
          await raf.setPosition(start);
          final data = await raf.read(want);
          completed[i] = data;
          deliver();
        }
      } catch (e) {
        if (!failed) {
          failed = true;
          print('[SMB] 预读失败: $e');
          controller.addError(e);
          controller.close();
        }
      } finally {
        if (raf != null) {
          try {
            await raf.close();
          } catch (_) {
            // 忽略关闭异常
          }
        }
      }
    }

    for (var i = 0; i < workers && i < totalBlocks; i++) {
      worker(i);
    }
    if (totalBlocks == 0) {
      controller.close();
    }

    return controller.stream;
  }

  SmbConnect _requireConnect() {
    final c = _connect;
    if (c == null) throw const NetworkClientException('SMB 尚未连接');
    return c;
  }

  NetworkFile _toFile(SmbFile f) {
    final isDir = f.isDirectory();
    return NetworkFile(
      name: f.name,
      path: f.path,
      isDirectory: isDir,
      size: isDir ? -1 : f.size,
      lastModified: _epochMs(f.lastModified),
      mimeType: isDir ? null : networkMimeTypeForFileName(f.name),
    );
  }

  /// smb_connect 的时间为 Windows FILETIME（100ns 自 1601-01-01），转成毫秒；
  /// 若已经是以毫秒为单位的 timestamp 或未知值（<=0）则直接回退。
  int _epochMs(int t) {
    if (t <= 0) return 0;
    if (t > 100000000000000) {
      return ((t - 116444736000000000) / 10000).floor();
    }
    return t;
  }

  String _friendly(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (lower.contains('logon') || lower.contains('password')) {
      return '用户名或密码错误';
    }
    if (lower.contains('denied') || lower.contains('access')) {
      return '拒绝访问（权限不足）';
    }
    if (lower.contains('not found') || lower.contains('no such')) {
      return '路径不存在';
    }
    if (s.trim().isEmpty) return 'SMB 请求失败';
    return s.length > 120 ? 'SMB 请求失败' : s;
  }
}