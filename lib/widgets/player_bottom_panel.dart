import 'package:flutter/material.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/player_panel.dart' show PlayerPanelPage;

/// 竖屏播放页的底部弹出面板导航器（与横屏 [PlayerPanelNavigator] 等价的小型实现）。
///
/// 面板内容通过 [PlayerBottomPanelNavigator.of] 获取，push/pop 二级页面。
/// 二级界面在面板内部就地切换（滑动 + 淡入），永不叠加第二个面板/弹窗。
/// 注意：`of` 必须用面板树内的 context（内容里先包一层 `Builder` 再取），
/// 不能用页面 State 的 context（同 PlayerPanelNavigator 的约定）。
class PlayerBottomPanelNavigator {
  final List<PlayerPanelPage> _pages;
  final VoidCallback _onChanged;

  PlayerBottomPanelNavigator(this._pages, this._onChanged);

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
  static PlayerBottomPanelNavigator of(BuildContext context) {
    final scope =
        context
            .dependOnInheritedWidgetOfExactType<_BottomPanelNavigatorScope>();
    assert(
      scope != null,
      'PlayerBottomPanelNavigator.of() called outside PlayerBottomPanel',
    );
    return scope!.navigator;
  }
}

class _BottomPanelNavigatorScope extends InheritedWidget {
  final PlayerBottomPanelNavigator navigator;

  const _BottomPanelNavigatorScope({
    required this.navigator,
    required super.child,
  });

  @override
  bool updateShouldNotify(_BottomPanelNavigatorScope oldWidget) =>
      navigator != oldWidget.navigator;
}

/// 从屏幕底部滑出的面板外壳（竖屏播放页专用，参照 src BottomSheet：
/// 遮罩 + 底部圆角 Surface + 标题 + 滚动内容 + 关闭）。
///
/// - 必须用 Material 外壳（面板内容含 ListTile/SwitchListTile/TextField，
///   要求 Material 祖先，防 "No Material widget found" 崩溃，同 PlayerPanel）；
/// - 面板内部维护页面栈，支持二级设置就地切换（[PlayerBottomPanelNavigator]）；
/// - 高度固定为屏幕 [heightFactor]（一级/二级/三级页面高度一致，
///   内容超出可滚动——比例/循环等短内容面板不再比更多面板矮）；
/// - 显示/隐藏由 [showPlayerBottomPanel] 统一处理（底部上滑 + 淡入）。
class PlayerBottomPanel extends StatefulWidget {
  final List<PlayerPanelPage> pages;
  final VoidCallback onClose;

  /// 面板高度占屏幕比例（竖屏下避免盖满画面）
  final double heightFactor;

  /// 是否启用进出场/页内切换动画（工作.md 第 7 点）
  final bool animate;

  const PlayerBottomPanel({
    super.key,
    required this.pages,
    required this.onClose,
    this.heightFactor = 0.42,
    this.animate = true,
  });

  @override
  State<PlayerBottomPanel> createState() => _PlayerBottomPanelState();
}

class _PlayerBottomPanelState extends State<PlayerBottomPanel> {
  // 保持同一 List 引用（导航器持有它）；外层重建时同步内容
  late final List<PlayerPanelPage> _pages = [...widget.pages];
  late final PlayerBottomPanelNavigator _navigator =
      PlayerBottomPanelNavigator(_pages, () => setState(() {}));

  @override
  void didUpdateWidget(covariant PlayerBottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外层每次 build 都会传入新的 pages（内含最新数据），必须同步，
    // 否则面板停留在首次打开时的旧数据（同 PlayerPanel 历史 bug）。
    _pages
      ..clear()
      ..addAll(widget.pages);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages.last;
    final panelHeight = MediaQuery.sizeOf(context).height * widget.heightFactor;
    return Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: widget.animate
            ? const Duration(milliseconds: 240)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        height: panelHeight,
        // SafeArea 放在 Material 内部：面板背景铺满（含手势条区域），
        // 内容避让底部系统导航键/手势条（竖屏下系统栏可见时）
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: _BottomPanelNavigatorScope(
            navigator: _navigator,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部拖拽指示条（iOS 风格小横条）
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildHeader(page.title),
                // 内容区：自适应高度，超限可滚动（面板内容均为可滚动组件）
                Flexible(
                  child: AnimatedSwitcher(
                    // 进场 200ms；退场仅 80ms（reverseDuration），
                    // 避免切换瞬间看到旧页面被点击时的水波纹残留；
                    // 工作.md 第 7 点：关闭播放界面动画后直接切换
                    duration: widget.animate
                        ? const Duration(milliseconds: 200)
                        : Duration.zero,
                    reverseDuration: widget.animate
                        ? const Duration(milliseconds: 80)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
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
                            begin: const Offset(0, 0.08),
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
                const SizedBox(height: 8),
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

/// 竖屏播放页公用入口：从屏幕底部弹出面板（倍速 / 超分 / 画面比例 /
/// 更多 / 编辑控制栏统一走这里）。
///
/// - 底部上滑 + 淡入动画（260ms easeOutCubic）；
/// - 遮罩点击关闭；
/// - 路由标记为播放页（[playerRouteName]），保证播放页全屏安全区不被破坏；
/// - 返回的 Future 在面板关闭时完成；
/// - [animate] 为 null 时跟随「播放器设置 → 启用播放界面动画」开关
///   （工作.md 第 7 点：关闭后面板直接出现/消失）。
Future<void> showPlayerBottomPanel(
  BuildContext context, {
  required List<PlayerPanelPage> pages,
  double heightFactor = 0.42,
  bool? animate,
}) {
  final withAnimation = animate ?? PlayerControlsSettings.instance.playerAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: withAnimation
        ? const Duration(milliseconds: 260)
        : Duration.zero,
    // 竖屏播放页弹出面板时仍视为播放页路由，避免 AppFrame 退出全屏（§4.3）
    routeSettings: const RouteSettings(name: playerRouteName),
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.bottomCenter,
      child: PlayerBottomPanel(
        pages: pages,
        heightFactor: heightFactor,
        animate: withAnimation,
        onClose: () => Navigator.of(context).pop(),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (!withAnimation) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
