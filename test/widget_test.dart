import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moumou/widgets/capsule_nav_bar.dart';

void main() {
  testWidgets('胶囊导航渲染测试', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CapsuleNavBar(
            items: const [
              CapsuleNavItem(
                icon: Icons.home,
                label: '首页',
                page: SizedBox(),
              ),
              CapsuleNavItem(
                icon: Icons.settings,
                label: '设置',
                page: SizedBox(),
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    // 胶囊导航（Telegram 风格）设计上所有标签都显示，仅样式区分选中态
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
