import 'package:flutter/material.dart';
import 'package:moumou/widgets/app_frame.dart';

/// 面板内导航的一层页面
class PlayerPanelPage {
  final String title;
  final Widget body;

  const PlayerPanelPage({required this.title, required this.body});
}

/// 面板导航器：面板内容通过 [PlayerPanelNavigator.of] 获取，push/pop 二级页面。
/// 二级界面在面板内部就地切换（滑动 + 淡入），永不叠加第二个面板/弹窗。
class PlayerPanelNavigator {
  final List<PlayerPanelPage> _pages;
  final VoidCallback _onChanged;

  PlayerPanelNavigator(this._pages, this._onChanged);

  bool get canPop => _pages.length > 1;

  void push(PlayerPanelPage page) {
    _pages.add(page);
    _onChanged();
  }

  void pop() {
    if (_pages.length > 1) {
      _pages.removeLast();
      _onChanged();
    }
  }

  /// 面板内容中获取当前导航器
  static PlayerPanelNavigator of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_PanelNavigatorScope>();
    assert(scope != null, 'PlayerPanelNavigator.of() called outside PlayerPanel');
    return scope!.navigator;
  }
}

class _PanelNavigatorScope extends InheritedWidget {
  final PlayerPanelNavigator navigator;

  const _PanelNavigatorScope({required this.navigator, required super.child});

  @override
  bool updateShouldNotify(_PanelNavigatorScope oldWidget) =>
      navigator != oldWidget.navigator;
}

/// 从屏幕右缘滑入的半透明设置面板（YouTube 风格）。
///
/// 面板内部维护页面栈，支持二级设置就地切换；
/// 显示/隐藏由 [showPlayerPanel] 统一处理。
class PlayerPanel extends StatefulWidget {
  final List<PlayerPanelPage> pages;
  final VoidCallback onClose;

  const PlayerPanel({super.key, required this.pages, required this.onClose});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  // 保持同一 List 引用（导航器持有它）；外层重建时同步内容
  late final List<PlayerPanelPage> _pages = [...widget.pages];
  late final PlayerPanelNavigator _navigator =
      PlayerPanelNavigator(_pages, () => setState(() {}));

  @override
  void didUpdateWidget(covariant PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外层每次 build 都会传入新的 pages（内含最新数据），必须同步，
    // 否则面板停留在首次打开时的旧数据（历史 bug：点预设无高亮/文本不变）。
    _pages
      ..clear()
      ..addAll(widget.pages);
  }

  @override
  Widget build(BuildContext context) {
    // 横屏下不超过 340dp；小屏按 72% 宽收缩
    final width = (MediaQuery.sizeOf(context).width * 0.72).clamp(0.0, 340.0);
    final page = _pages.last;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: double.infinity,
        // 必须用 Material 外壳：面板内容含 ListTile/SwitchListTile/TextField，
        // 它们要求 Material 祖先（提供墨迹/水波纹），普通 Container 会抛
        // "No Material widget found"（历史崩溃：更多面板红底黄字）。
        child: Material(
          color: const Color(0xE61C1C1E),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: _PanelNavigatorScope(
            navigator: _navigator,
            child: Column(
              children: [
                _buildHeader(page.title),
                Expanded(
                  child: AnimatedSwitcher(
                    // 进场 200ms；退场仅 80ms（reverseDuration），
                    // 避免切换瞬间看到旧页面被点击时的水波纹残留
                    duration: const Duration(milliseconds: 200),
                    reverseDuration: const Duration(milliseconds: 80),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // 内容顶部对齐（默认 Stack 居中会让内容较短的面板
                    // 垂直居中，如画面比例面板）
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.08, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(page.title),
                      child: page.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          if (_navigator.canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: '返回',
              onPressed: _navigator.pop,
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: '关闭',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

/// 公用入口：从屏幕右缘弹出面板（倍速 / 更多 / 编辑控制栏等统一走这里）。
///
/// - 遮罩点击关闭；滑入 + 淡入动画（220ms easeOutCubic）；
/// - 路由标记为播放页（[playerRouteName]），保证播放页全屏安全区不被破坏；
/// - 返回的 Future 在面板关闭时完成。
Future<void> showPlayerPanel(
  BuildContext context, {
  required List<PlayerPanelPage> pages,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    // 播放页弹出面板时仍视为播放页路由，避免 AppFrame 退出全屏（§4.3）
    routeSettings: const RouteSettings(name: playerRouteName),
    pageBuilder: (context, animation, secondaryAnimation) => PlayerPanel(
      pages: pages,
      onClose: () => Navigator.of(context).pop(),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
