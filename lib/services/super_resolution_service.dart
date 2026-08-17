import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/super_resolution_mode.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 超分辨率服务：管理模式与质量选择 + 记忆开关（持久化）+ 把 Anime4K
/// 着色器从 assets 拷贝到应用目录 + 通过 mpv glsl-shaders 应用到播放器。
///
/// 全局单例（同 [PlayerControlsSettings] 模式），ChangeNotifier + shared_preferences
/// 持久化；播放页的超分面板与设置页共同监听。
///
/// 记忆语义（参考 mpv-android-anime4k）：
/// - 「记忆超分模式」默认关闭：每次启动播放器都从关闭/均衡开始；
/// - 开启后：自动应用上次设置的超分模式与超分质量到所有视频；
/// - 无论开关状态，最近一次手动设置的「模式/质量」都会记录为 last，
///   供开启记忆时恢复。
///
/// 着色器必须以「文件绝对路径」交给 mpv（libmpv 不支持直接读 assets），
/// 所以首次使用前把 assets/shaders 下的 .glsl 拷贝到应用支持目录，之后直接复用。
class SuperResolutionService extends ChangeNotifier {
  static final SuperResolutionService instance = SuperResolutionService._();

  SuperResolutionService._();

  static const _keyLastMode = 'super_resolution_last_mode';
  static const _keyLastQuality = 'super_resolution_last_quality';
  static const _keyRemember = 'super_resolution_remember';

  SuperResolutionMode _mode = SuperResolutionMode.off;
  SuperResolutionQuality _quality = SuperResolutionQuality.balanced;
  SuperResolutionMode _lastMode = SuperResolutionMode.off;
  SuperResolutionQuality _lastQuality = SuperResolutionQuality.balanced;
  bool _remember = false;
  Directory? _shadersDirectory;

  /// 当前超分模式
  SuperResolutionMode get mode => _mode;

  /// 当前超分质量档（流畅/均衡/高清，默认均衡）
  SuperResolutionQuality get quality => _quality;

  /// 是否记忆超分模式（默认关闭；开启后自动应用上次设置到所有视频）
  bool get remember => _remember;

  /// 着色器所在目录（[apply] 内部保证已就绪；拷贝失败时为 null）
  Directory? get shadersDirectory => _shadersDirectory;

  /// 启动时加载（main.dart 调用）。
  /// 记忆开启 → 恢复上次的模式+质量；关闭 → 回到关闭/均衡。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lastMode = SuperResolutionMode.byId(prefs.getString(_keyLastMode));
    _lastQuality = SuperResolutionQuality.fromIndex(prefs.getInt(_keyLastQuality));
    _remember = prefs.getBool(_keyRemember) ?? false;
    if (_remember) {
      _mode = _lastMode;
      _quality = _lastQuality;
    } else {
      _mode = SuperResolutionMode.off;
      _quality = SuperResolutionQuality.balanced;
    }
    notifyListeners();
  }

  /// 切换模式；总是记录为「上次设置」（供记忆开启时恢复），
  /// [player] 非空时立即应用到播放器。
  Future<void> setMode(SuperResolutionMode mode, {Player? player}) async {
    _mode = mode;
    _lastMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastMode, mode.id);
    if (player != null) {
      await apply(player);
    }
  }

  /// 切换质量档（流畅/均衡/高清）；总是记录为「上次设置」，
  /// 非关闭且 [player] 非空时用新质量重建着色器链并重新应用。
  Future<void> setQuality(SuperResolutionQuality quality,
      {Player? player}) async {
    _quality = quality;
    _lastQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastQuality, quality.index);
    if (player != null && _mode != SuperResolutionMode.off) {
      await apply(player);
    }
  }

  /// 记忆超分模式开关（默认关闭）。
  /// 开启：立即恢复上次的模式+质量；关闭：当前会话回到关闭/均衡。
  /// [player] 非空时把变化立即应用到播放器（关闭记忆 → 清除着色器）。
  Future<void> setRemember(bool remember, {Player? player}) async {
    if (_remember == remember) return;
    _remember = remember;
    if (remember) {
      _mode = _lastMode;
      _quality = _lastQuality;
    } else {
      _mode = SuperResolutionMode.off;
      _quality = SuperResolutionQuality.balanced;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemember, remember);
    if (player != null) {
      await apply(player);
    }
  }

  /// 进入播放器时调用（播放页 initState）：未开启记忆时，本次会话
  /// 从「关闭 / 均衡」开始 —— 无论上次会话/上次视频设置过什么，
  /// 退出播放或重启后都回到默认关闭（记忆开启时保持上次设置）。
  void enterPlayer() {
    if (!_remember) {
      _mode = SuperResolutionMode.off;
      _quality = SuperResolutionQuality.balanced;
      notifyListeners();
    }
  }

  /// 把当前模式应用到 [player]（打开媒体后调用；切档/下一集后重放）。
  ///
  /// 底层走 mpv 命令：`change-list glsl-shaders set|clr`（与 Kazumi / PiliPlus 一致）。
  Future<void> apply(Player player) async {
    final native = player.platform as NativePlayer;
    try {
      await native.waitForPlayerInitialization;
      await native.waitForVideoControllerInitializationIfAttached;
      if (_mode == SuperResolutionMode.off) {
        await native.command(const [
          'change-list',
          'glsl-shaders',
          'clr',
          '',
        ]);
        return;
      }
      final dir = await _ensureShadersCopied();
      final chain = buildAnime4KChain(_mode, _quality);
      final paths = chain
          .map((s) => p.join(dir.path, s))
          .join(Platform.isWindows ? ';' : ':');
      await native.command([
        'change-list',
        'glsl-shaders',
        'set',
        paths,
      ]);
    } catch (e) {
      // 播放器未就绪 / 渲染器不支持时静默失败，不打断播放
      debugPrint('SuperResolutionService: failed to apply shaders: $e');
    }
  }

  /// 测试用：恢复默认值（单例在测试间共享，避免状态泄漏）
  @visibleForTesting
  void reset() {
    _mode = SuperResolutionMode.off;
    _quality = SuperResolutionQuality.balanced;
    _lastMode = SuperResolutionMode.off;
    _lastQuality = SuperResolutionQuality.balanced;
    _remember = false;
    notifyListeners();
  }

  /// 确保 assets/shaders 下的 .glsl 已拷贝到应用支持目录（已存在则跳过）。
  Future<Directory> _ensureShadersCopied() async {
    final dir = _shadersDirectory ?? await _createShadersDirectory();
    _shadersDirectory = dir;

    // 枚举全部 mode × quality 组合可能用到的着色器文件
    final needed = <String>{
      for (final m in SuperResolutionMode.values)
        for (final q in SuperResolutionQuality.values)
          ...buildAnime4KChain(m, q),
    };
    for (final name in needed) {
      final target = File(p.join(dir.path, name));
      if (await target.exists()) continue;
      try {
        final data = await rootBundle.load('assets/shaders/$name');
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } catch (e) {
        debugPrint('SuperResolutionService: copy shader $name failed: $e');
      }
    }
    return dir;
  }

  Future<Directory> _createShadersDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'anime_shaders'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
