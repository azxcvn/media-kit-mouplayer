import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moumou/services/playback_progress_service.dart';

/// 播放页：默认横屏播放，自定义现代化控制 UI
class PlayerPage extends StatefulWidget {
  final String path;
  final String title;

  const PlayerPage({super.key, required this.path, required this.title});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  double _speed = 1.0;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.path));

    // 默认强制横屏 + 沉浸式全屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _subs.add(
      _player.stream.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );

    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _resetHideTimer();
  }

  Future<void> _togglePlay() async {
    await _player.playOrPause();
    _resetHideTimer();
  }

  Future<void> _cycleSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 2.0];
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    _speed = next;
    await _player.setRate(next);
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  /// 退出播放器：先保存进度、恢复竖屏，再返回
  Future<void> _exitPlayer() async {
    _saveProgress();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop();
  }

  /// 记录播放进度（播了一部分才记，避免污染"没看过的视频"）
  void _saveProgress() {
    if (_position.inMilliseconds > 0 &&
        _duration.inMilliseconds > 0 &&
        _position < _duration) {
      PlaybackProgressService.instance.save(widget.path, _position);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _saveProgress();
    // 退出时强制恢复竖屏和系统 UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频画面（禁用默认控件）
          Positioned.fill(
            child: Video(controller: _controller, controls: NoVideoControls),
          ),
          // 点击层：切换控制层显隐
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          // 控制层
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [_buildTopBar(), const Spacer(), _buildBottomBar()],
              ),
            ),
          ),
          // 中央大播放按钮（暂停时显示）
          if (!_playing && _controlsVisible)
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _exitPlayer,
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _duration.inMilliseconds > 0 ? _duration : Duration.zero;
    final current = _dragPosition ?? _position;
    final maxMs = total.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final valueMs = current.inMilliseconds
        .toDouble()
        .clamp(0.0, total.inMilliseconds.toDouble())
        .toDouble();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.2),
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: valueMs,
                onChanged: (v) {
                  setState(
                    () => _dragPosition = Duration(milliseconds: v.round()),
                  );
                  _resetHideTimer();
                },
                onChangeEnd: (v) {
                  _player.seek(Duration(milliseconds: v.round()));
                  _dragPosition = null;
                  _resetHideTimer();
                },
              ),
            ),
            // 按钮行
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_fmt(current)} / ${_fmt(total)}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cycleSpeed,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_speed}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
