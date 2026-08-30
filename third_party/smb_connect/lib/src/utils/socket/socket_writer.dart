import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/src/utils/extensions.dart';

class SocketWriter {
  final bool debugPrint;
  final Socket _socket;

  SocketWriter(this._socket, {this.debugPrint = false});

  int lastWrite = 0;

  // 注意：这里不能是 async void。否则 _socket.add(buf) 抛出的异常会绕过调用方
  // （doSend → sendrecv）变成 Zone 级 Unhandled Exception，导致 socket 关闭后
  // 大量刷屏且无法被上层 catch。保持同步，让异常沿调用栈正常向上传播。
  void write(Uint8List buffer, int offset, int length) {
    var buf = Uint8List.view(buffer.buffer, offset, length);
    _socket.add(buf);
    lastWrite += buf.length;
    if (debugPrint) {
      print("write[$length]: ${buf.toHexString2(offset, length)}");
    }
  }

  Future<void> flush() async {
    if (debugPrint) {
      print("write flush $lastWrite");
    }
    await _socket.flush();
    lastWrite = 0;
  }
}
