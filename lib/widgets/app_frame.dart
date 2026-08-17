import 'package:flutter/material.dart';

/// 播放页路由标识：播放页 push 时需携带 RouteSettings(name: playerRouteName)
const String playerRouteName = 'player';

/// 全局框架：包裹整个 Navigator，处理系统安全区与播放页全屏。
///
/// - 普通页面：底部避让系统导航键（三大金刚键），背景为主题色；
/// - 播放页（NavigatorObserver 自动检测）：背景黑色、不消费任何系统栏
///   inset（真正全屏），避免横屏时挖孔/导航栏区域露出浅色背景（白色条）。
///
/// 注意 left/right 恒为 false：横屏时挖孔在物理左/右侧，若 SafeArea 消费
/// 左右 inset，整个界面会被挖孔挤到一侧并露出背景色。
class AppFrame extends StatelessWidget {
  final Widget child;

  const AppFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppFrameObserver.instance.isPlayerTop,
      builder: (context, isPlayer, _) => ColoredBox(
        color: isPlayer
            ? Colors.black
            : Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          left: false,
          top: false,
          right: false,
          bottom: !isPlayer,
          child: child,
        ),
      ),
    );
  }
}

/// 路由观察者：监听栈顶是否为播放页，供 [AppFrame] 切换全屏行为。
/// 全局单例，挂到 MaterialApp.navigatorObservers。
class AppFrameObserver extends NavigatorObserver {
  AppFrameObserver._();

  static final AppFrameObserver instance = AppFrameObserver._();

  /// 栈顶是否为播放页
  final ValueNotifier<bool> isPlayerTop = ValueNotifier(false);

  final List<Route<dynamic>> _stack = [];

  void _update() {
    final top = _stack.isEmpty ? null : _stack.last;
    isPlayerTop.value = top != null && _isPlayerRoute(top);
  }

  bool _isPlayerRoute(Route<dynamic> route) {
    return route.settings.name == playerRouteName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute != null) _stack.add(newRoute);
    _update();
  }

  /// 测试用：重置栈状态
  @visibleForTesting
  void reset() {
    _stack.clear();
    isPlayerTop.value = false;
  }
}
