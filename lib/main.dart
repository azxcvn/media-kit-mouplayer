import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/pages/home/home_page.dart';
import 'package:moumou/pages/settings/settings_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/theme/app_theme.dart';
import 'package:moumou/theme/theme_controller.dart';
import 'package:moumou/widgets/capsule_nav_bar.dart';
import 'package:moumou/widgets/main_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MoumouApp());
}

class MoumouApp extends StatefulWidget {
  const MoumouApp({super.key});

  @override
  State<MoumouApp> createState() => _MoumouAppState();
}

class _MoumouAppState extends State<MoumouApp> {
  final ThemeController _themeController = ThemeController();
  final ViewSettings _viewSettings = ViewSettings();

  @override
  void initState() {
    super.initState();
    _themeController.load();
    _viewSettings.load();
    PlaybackProgressService.instance.load();
  }

  @override
  void dispose() {
    _themeController.dispose();
    _viewSettings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        final seed = _themeController.seedColor;
        final mode = _themeController.mode;
        final variant = _themeController.variant;

        final light = AppTheme.light(seed, variant);
        // AMOLED 模式下深色主题换成纯黑版本
        final dark = mode == AppThemeMode.amoled
            ? AppTheme.amoled(seed, variant)
            : AppTheme.dark(seed, variant);
        final themeMode = switch (mode) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.amoled => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        };

        return MaterialApp(
          title: '小牛Player',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: themeMode,
          // 全局处理系统底部导航键（三大金刚键）安全区：
          // 所有页面（含以后新增的）自动避开底部安全区，无需每页手动处理。
          // 顶部不处理（AppBar 自行适配状态栏）；播放页为横屏沉浸式，
          // 横屏下底部安全区为 0，不受影响。
          // ColoredBox：让 SafeArea 底部的系统导航栏区域与页面背景同色
          // （否则该区域在 Navigator 之外，会露出窗口默认黑色背景）。
          builder: (context, child) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(top: false, bottom: true, child: child!),
          ),
          home: MainScaffold(
            items: [
              CapsuleNavItem(
                icon: Icons.home_outlined,
                label: '首页',
                page: HomePage(viewSettings: _viewSettings),
              ),
              CapsuleNavItem(
                icon: Icons.settings_outlined,
                label: '设置',
                page: SettingsPage(controller: _themeController),
              ),
            ],
          ),
        );
      },
    );
  }
}
