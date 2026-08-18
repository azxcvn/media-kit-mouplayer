/// 循环播放模式。
///
/// - [off]：关闭循环（播完按「自动连播 / 自动退出 / 自动暂停」逻辑走）
/// - [loopAll]：列表循环（播放列表播完最后一集后回到第一集继续）
/// - [repeatOne]：单集循环（当前视频播完自动从头重播）
///
/// 持久化按枚举 index（与 DoubleTapMode / PlayerVideoFit 同一约定，
/// 见 PlayerControlsSettings），新增模式只能追加到末尾，勿改已有顺序。
enum LoopMode {
  off('关闭'),
  loopAll('列表循环'),
  repeatOne('单集循环');

  /// 设置界面展示名
  final String label;

  const LoopMode(this.label);
}
