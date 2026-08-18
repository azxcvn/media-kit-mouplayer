import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/player_loop.dart';
import 'package:moumou/utils/playback_completion.dart';

/// resolveEndOfFileAction 纯函数测试：
/// handleEndOfFile 优先级链 = 单集循环 → 自动连播 → 列表循环 → 自动退出 → 自动暂停。
void main() {
  group('resolveEndOfFileAction：优先级链', () {
    test('单集循环最高优先：无视其它设置永远重播当前集', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.repeatOne,
          autoNext: true,
          autoExit: true,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.replayCurrent,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.repeatOne,
          autoNext: false,
          autoExit: false,
          hasPlaylist: false,
          hasNext: false,
        ),
        EndOfFileAction.replayCurrent,
      );
    });

    test('自动连播：autoNext 开且有下一集 → 下一集（优先于列表循环）', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.loopAll,
          autoNext: true,
          autoExit: true,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.playNext,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: true,
          autoExit: true,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.playNext,
      );
    });

    test('列表循环：无下一集时回到列表第一集', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.loopAll,
          autoNext: true,
          autoExit: true,
          hasPlaylist: true,
          hasNext: false,
        ),
        EndOfFileAction.playFirst,
      );
      // autoNext 关但列表循环开：播完也回第一集
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.loopAll,
          autoNext: false,
          autoExit: false,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.playFirst,
      );
    });

    test('列表循环但无播放列表：落到自动退出/自动暂停', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.loopAll,
          autoNext: false,
          autoExit: true,
          hasPlaylist: false,
          hasNext: false,
        ),
        EndOfFileAction.exitPlayer,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.loopAll,
          autoNext: false,
          autoExit: false,
          hasPlaylist: false,
          hasNext: false,
        ),
        EndOfFileAction.pauseAtEnd,
      );
    });

    test('最后一个视频（autoNext 开但无下一集）+ autoExit → 退出', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: true,
          autoExit: true,
          hasPlaylist: true,
          hasNext: false,
        ),
        EndOfFileAction.exitPlayer,
      );
    });

    test('autoNext 关 + autoExit 开 → 退出（src closeAfterEOF 语义）', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: false,
          autoExit: true,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.exitPlayer,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: false,
          autoExit: true,
          hasPlaylist: true,
          hasNext: false,
        ),
        EndOfFileAction.exitPlayer,
      );
    });

    test('autoExit 关 → 自动暂停停在末尾', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: false,
          autoExit: false,
          hasPlaylist: true,
          hasNext: true,
        ),
        EndOfFileAction.pauseAtEnd,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: true,
          autoExit: false,
          hasPlaylist: true,
          hasNext: false,
        ),
        EndOfFileAction.pauseAtEnd,
      );
    });

    test('单视频无播放列表：autoExit 开退出，关则暂停', () {
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: true,
          autoExit: true,
          hasPlaylist: false,
          hasNext: false,
        ),
        EndOfFileAction.exitPlayer,
      );
      expect(
        resolveEndOfFileAction(
          loopMode: LoopMode.off,
          autoNext: true,
          autoExit: false,
          hasPlaylist: false,
          hasNext: false,
        ),
        EndOfFileAction.pauseAtEnd,
      );
    });
  });
}
