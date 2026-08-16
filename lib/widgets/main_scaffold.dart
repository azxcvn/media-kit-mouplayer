import 'package:flutter/material.dart';
import 'package:moumou/widgets/capsule_nav_bar.dart';

/// 主壳：负责页面切换 + 胶囊底部导航
///
/// 胶囊导航为悬浮样式：通过 Stack 叠加在页面内容之上，
/// 不占据独立布局行，页面内容可延伸到屏幕底部。
class MainScaffold extends StatefulWidget {
  final List<CapsuleNavItem> items;

  const MainScaffold({super.key, required this.items});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;
  late final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 页面内容全屏（延伸到屏幕底部），胶囊导航悬浮其上
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _index = i),
            children: widget.items.map((e) => e.page).toList(),
          ),
          // 悬浮胶囊导航：Positioned 叠加，不占布局行
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CapsuleNavBar(
              items: widget.items,
              selectedIndex: _index,
              onSelected: _goTo,
            ),
          ),
        ],
      ),
    );
  }
}
