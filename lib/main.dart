import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/pages/home/home_page.dart';
import 'package:moumou/pages/settings/settings_page.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/theme/app_theme.dart';
import 'package:moumou/theme/theme_controller.dart';
import 'package:moumou/widgets/app_frame.dart';
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
    PlayerControlsSettings.instance.load();
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
          // 全局框架：安全区 + 播放页全屏（详见 AppFrame）
          builder: (context, child) => AppFrame(child: child!),
          // 路由观察者：AppFrame 据此检测播放页，切换全屏行为
          navigatorObservers: [AppFrameObserver.instance],
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
