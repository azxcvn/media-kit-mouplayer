import 'package:moumou/services/device_services.dart';

/// 缩略图预生成服务：**用户第一次拖动进度条时**由播放页触发，
/// 按自适应间隔把整段视频的缩略图逐桶预热到 [DeviceServices] 的内存缓存
/// （原生侧同时落盘），让「快速拖动进度条」也能即时显示最近帧，
/// 而不是等精确解码。
///
/// - 采样间隔 [intervalFor]：目标约 96 帧，间隔取整到 5 秒（最短 2 秒）；
/// - 预热顺序：从当前拖动位置向外扩散（先近后远），优先覆盖拖动起点附近；
/// - 与拖动时的实时抓帧共享同一缓存与在飞去重（不重复解码）；
/// - 内存命中（[DeviceServices.peekFrame]）直接跳过；每个桶间让出事件循环。
///
/// 页面局部使用（播放页持有实例），切集/退出时 [cancel]。
/// 不拖进度条的用户全程零后台解码、零缓存开销。
class ThumbnailPreloadService {
  /// 目标采样帧数（整段视频）
  static const int targetCells = 96;

  /// 采样间隔（毫秒）：目标约 [targetCells] 帧，取整到 5 秒，最短 2 秒
  static int intervalFor(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) return 5000;
    final raw = ms / targetCells;
    final rounded = ((raw / 5000).ceil() * 5000).clamp(2000, 60000);
    return rounded;
  }

  String? _activePath;
  bool _cancelled = true;

  /// 当前是否正在为 [path] 预热
  bool isActiveFor(String path) => _activePath == path && !_cancelled;

  /// 开始预热 [path]（从 [fromMs] 处向外扩散）。
  /// 重复调用会先取消上一次预热。
  void start(String path, int durationMs, {int fromMs = 0}) {
    cancel();
    if (durationMs <= 0) return;
    _activePath = path;
    _cancelled = false;
    final interval = intervalFor(Duration(milliseconds: durationMs));
    _run(path, durationMs, interval, fromMs);
  }

  /// 停止预热（切集 / 退出播放时调用）
  void cancel() {
    _cancelled = true;
    _activePath = null;
  }

  Future<void> _run(
    String path,
    int durationMs,
    int interval,
    int fromMs,
  ) async {
    // 全部采样点，按与 fromMs 的距离排序（先近后远）
    final buckets = <int>[];
    for (var b = 0; b <= durationMs; b += interval) {
      buckets.add(b);
    }
    buckets.sort((a, b) {
      final da = (a - fromMs).abs();
      final db = (b - fromMs).abs();
      return da.compareTo(db);
    });

    for (final b in buckets) {
      if (_cancelled || _activePath != path) return;
      // 内存已缓存（含拖动时刚解码的）→ 跳过
      if (DeviceServices.peekFrame(path, b) == null) {
        await DeviceServices.getVideoFrameAt(path, b);
      }
      // 让出事件循环，避免长时间占用
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}
