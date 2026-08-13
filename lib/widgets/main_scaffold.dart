import 'package:flutter/material.dart';
import 'package:moumou/widgets/capsule_nav_bar.dart';

/// 主壳：负责页面切换 + 胶囊底部导航
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _index = i),
        children: widget.items.map((e) => e.page).toList(),
      ),
      bottomNavigationBar: CapsuleNavBar(
        items: widget.items,
        selectedIndex: _index,
        onSelected: _goTo,
      ),
    );
  }
}
