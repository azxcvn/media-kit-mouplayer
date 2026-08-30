/// FTP 客户端（纯 Dart，基于 `dart:io` Socket，学习 mpvRx `FtpClient` 采用
/// Apache Commons Net 的分层思路，但自行实现控制/数据双连接与被动模式）。
///
/// 要点：
/// - 浏览（列表/大小）走一条共享控制连接；流式传输（[openStream]）为专用
///   控制连接，避免与浏览共享状态；
/// - 目录列表优先 RFC 3659 `MLSD`，服务器不支持时回退 Unix `LIST`；
/// - 偏移读取用 `REST`，不接受时直接报错而非返回损坏的偏移流。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:moumou/models/network_connection.dart';
import 'package:moumou/models/network_file.dart';
import 'package:moumou/services/network/network_client.dart';
import 'package:moumou/utils/ftp_parser.dart';
import 'package:moumou/utils/network_mime_types.dart';
import 'package:moumou/utils/network_path.dart';

class FtpClient implements NetworkClient {
  final NetworkConnection connection;

  FtpClient(this.connection);

  _FtpControl? _control;

  @override
  bool isConnected() => _control?.isOpen ?? false;

  @override
  Future<void> connect() async {
    await disconnect();
    final socket = await Socket.connect(
      connection.host,
      connection.port,
      timeout: const Duration(milliseconds: 15000),
    );
    final ctrl = _FtpControl(socket, connection.host);
    try {
      await ctrl.readReply();
      _expect(ctrl.replyCode == 220, 'FTP 服务器拒绝连接（代码 ${ctrl.replyCode}）');
      await _login(ctrl);
      final root = _remotePath(NetworkPath.root);
      if (root != '/') {
        await ctrl.sendCommand('CWD $root');
        _expect(ctrl.replyCode == 250, 'FTP 根目录不可用（代码 ${ctrl.replyCode}）');
      }
      _control = ctrl;
    } catch (_) {
      ctrl.close();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final ctrl = _control;
    _control = null;
    ctrl?.close();
  }

  @override
  Future<List<NetworkFile>> listFiles(String path) async {
    final ctrl = _requireControl();
    final dir = NetworkPath.from(path);

    final mlsd = await _tryMlsd(ctrl, dir);
    final List<FtpListEntry> entries;
    if (mlsd != null) {
      entries = mlsd.map(parseMlsdLine).whereType<FtpListEntry>().toList();
    } else {
      final unix = await _tryListUnix(ctrl, dir);
      entries = unix.map(parseUnixListLine).whereType<FtpListEntry>().toList();
    }

    final files = <NetworkFile>[];
    for (final e in entries) {
      final childPath = _childOrNull(dir, e.name);
      if (childPath == null) continue;
      files.add(
        NetworkFile(
          name: e.name,
          path: childPath,
          isDirectory: e.isDirectory,
          size: e.isDirectory ? -1 : e.size,
          lastModified: e.lastModifiedMs,
          mimeType: e.isDirectory ? null : networkMimeTypeForFileName(e.name),
        ),
      );
    }
    return files;
  }

  @override
  Future<int> getFileSize(String path) async {
    final ctrl = _requireControl();
    final p = _remotePath(NetworkPath.from(path));

    await ctrl.sendCommand('SIZE $p');
    if (ctrl.replyCode == 213) {
      final size = int.tryParse(ctrl.replyText.substring(4).trim());
      if (size != null && size >= 0) return size;
    }
    await ctrl.sendCommand('MLST $p');
    if (ctrl.replyCode == 250) {
      final m = RegExp(r'size=(\d+)', caseSensitive: false)
          .firstMatch(ctrl.replyText);
      final size = m == null ? null : int.tryParse(m.group(1)!);
      if (size != null && size >= 0) return size;
    }
    return -1;
  }

  @override
  Future<Stream<List<int>>> openStream(String path, {int offset = 0}) async {
    final socket = await Socket.connect(
      connection.host,
      connection.port,
      timeout: const Duration(milliseconds: 15000),
    );
    final ctrl = _FtpControl(socket, connection.host);
    try {
      await ctrl.readReply();
      _expect(ctrl.replyCode == 220, 'FTP 服务器拒绝连接（代码 ${ctrl.replyCode}）');
      await _login(ctrl);

      if (offset > 0) {
        await ctrl.sendCommand('REST $offset');
        _expect(ctrl.replyCode == 350, 'FTP 服务器不支持断点续传（REST）');
      }

      final data = await ctrl.openPassiveData();
      await ctrl.sendCommand('RETR ${_remotePath(NetworkPath.from(path))}');
      _expect(
        ctrl.replyCode == 150 || ctrl.replyCode == 125,
        'FTP 服务器拒绝文件传输（代码 ${ctrl.replyCode}）',
      );
      return _managedStream(data, ctrl);
    } catch (_) {
      ctrl.close();
      rethrow;
    }
  }

  Future<void> _login(_FtpControl ctrl) async {
    final user = connection.isAnonymous ? 'anonymous' : connection.username;
    await ctrl.sendCommand('USER $user');
    if (ctrl.replyCode == 331) {
      final pass = connection.isAnonymous ? 'anonymous@' : connection.password;
      await ctrl.sendCommand('PASS $pass');
    }
    _expect(ctrl.replyCode == 230 || ctrl.replyCode == 202, 'FTP 登录失败，请检查账号密码');
    await ctrl.sendCommand('TYPE I');
    _expect(ctrl.replyCode == 200, 'FTP 服务器拒绝二进制模式');
    await ctrl.sendCommand('OPTS UTF8 ON'); // 尽力而为，忽略失败
  }

  Future<List<String>?> _tryMlsd(_FtpControl ctrl, NetworkPath dir) async {
    final data = await ctrl.openPassiveData();
    try {
      await ctrl.sendCommand('MLSD ${_remotePath(dir)}');
      if (ctrl.replyCode != 150 && ctrl.replyCode != 125) {
        return null; // 服务器不支持 MLSD
      }
      final text = await _readAllUtf8(data);
      await ctrl.readReply(); // 226
      return text.split('\n');
    } finally {
      data.destroy();
    }
  }

  Future<List<String>> _tryListUnix(_FtpControl ctrl, NetworkPath dir) async {
    final data = await ctrl.openPassiveData();
    try {
      await ctrl.sendCommand('LIST ${_remotePath(dir)}');
      _expect(
        ctrl.replyCode == 150 || ctrl.replyCode == 125,
        'FTP 目录列表失败（代码 ${ctrl.replyCode}）',
      );
      final text = await _readAllUtf8(data);
      await ctrl.readReply(); // 226
      return text.split('\n');
    } finally {
      data.destroy();
    }
  }

  Future<String> _readAllUtf8(Socket socket) async {
    final bytes = <int>[];
    await for (final chunk in socket) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _remotePath(NetworkPath p) {
    final segments = [...NetworkPath.from(connection.path).segments, ...p.segments];
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  _FtpControl _requireControl() {
    final c = _control;
    if (c == null || !c.isOpen) {
      throw const NetworkClientException('FTP 未连接');
    }
    return c;
  }

  static void _expect(bool condition, String message) {
    if (!condition) throw NetworkClientException(message);
  }

  static String? _childOrNull(NetworkPath dir, String name) {
    try {
      return dir.child(name).value;
    } catch (_) {
      return null;
    }
  }

  Stream<List<int>> _managedStream(Socket data, _FtpControl ctrl) {
    final controller = StreamController<List<int>>();
    StreamSubscription<List<int>>? sub;
    var cleaned = false;

    void cleanup() {
      if (cleaned) return;
      cleaned = true;
      ctrl.close();
    }

    controller.onListen = () {
      sub = data.listen(
        (chunk) {
          if (!controller.isClosed) controller.add(chunk);
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
          cleanup();
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
          cleanup();
        },
      );
    };
    controller.onCancel = () {
      sub?.cancel();
      data.destroy();
      cleanup();
    };
    return controller.stream;
  }
}

/// 单条 FTP 控制连接：按行读取应答（兼容多行 `code-... code ...` 格式），
/// 并提供被动模式数据连接建立能力。
class _FtpControl {
  final Socket _socket;
  final String host;
  late final StreamIterator<String> _lines;

  int replyCode = 0;
  String replyText = '';
  bool _closed = false;

  _FtpControl(this._socket, this.host) {
    _lines = StreamIterator<String>(
      _socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  bool get isOpen => !_closed;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _socket.destroy();
    } catch (_) {
      // 忽略关闭异常。
    }
  }

  Future<void> readReply() async {
    final buffer = StringBuffer();
    if (!await _lines.moveNext()) {
      throw const NetworkClientException('FTP 连接被服务器关闭');
    }
    final first = _lines.current;
    buffer.write(first);

    final code = int.tryParse(first.length >= 3 ? first.substring(0, 3) : '');
    if (code == null) {
      throw const NetworkClientException('FTP 服务器返回异常响应');
    }
    final multiline = first.length >= 4 && first[3] == '-';
    if (multiline) {
      final terminator = '$code ';
      while (true) {
        if (!await _lines.moveNext()) {
          throw const NetworkClientException('FTP 连接中断');
        }
        final line = _lines.current;
        buffer.write('\n$line');
        if (line.startsWith(terminator)) break;
      }
    }
    replyCode = code;
    replyText = buffer.toString();
  }

  Future<void> sendCommand(String command) async {
    _socket.write('$command\r\n');
    await _socket.flush();
    await readReply();
  }

  /// 建立被动模式数据连接：优先 EPSV（IPv6 友好），回退 PASV。
  Future<Socket> openPassiveData() async {
    await sendCommand('EPSV');
    if (replyCode == 229) {
      final m = RegExp(r'\(\|\|\|(\d+)\|\)').firstMatch(replyText);
      if (m != null) {
        final port = int.parse(m.group(1)!);
        return Socket.connect(host, port,
            timeout: const Duration(milliseconds: 15000));
      }
    }
    await sendCommand('PASV');
    if (replyCode != 227) {
      throw const NetworkClientException('FTP 服务器不支持被动模式');
    }
    final m = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
        .firstMatch(replyText);
    if (m == null) {
      throw const NetworkClientException('FTP 被动模式响应无法解析');
    }
    var ip =
        '${m.group(1)!}.${m.group(2)!}.${m.group(3)!}.${m.group(4)!}';
    if (ip == '0.0.0.0') ip = host;
    final port = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
    return Socket.connect(ip, port,
        timeout: const Duration(milliseconds: 15000));
  }
}