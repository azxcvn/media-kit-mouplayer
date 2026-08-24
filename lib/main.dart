import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/pages/home/home_page.dart';
import 'package:moumou/pages/settings/settings_page.dart';
import 'package:moumou/services/crash_log_service.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/services/playback_progress_service.dart';
import 'package:moumou/services/player_controls_settings.dart';
import 'package:moumou/services/subtitle_settings.dart';
import 'package:moumou/services/super_resolution_service.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/theme/app_theme.dart';
import 'package:moumou/theme/theme_controller.dart';
import 'package:moumou/widgets/app_frame.dart';
import 'package:moumou/widgets/capsule_nav_bar.dart';
import 'package:moumou/widgets/main_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 崩溃缓存机制：Dart 侧未捕获异常也写入崩溃日志目录（原生 CrashHandler
  // 负责 Java/Kotlin 崩溃；两者同目录，错误日志页统一查看/导出/复制）
  MediaKit.ensureInitialized();
  // FlutterError（框架层）异常也写日志 —— 必须先于 runApp 挂钩子
  final oldError = FlutterError.onError;
  FlutterError.onError = (details) {
    oldError?.call(details);
    CrashLogService.appendDartLog(
      '━━━ Flutter 异常 ${DateTime.now()} ━━━\n'
      '${details.exception}\n${details.stack ?? ''}\n'
      '━━━━━━━━━━━━━━━━━━━━━━━━',
    );
  };
  // Zone 层兜底：异步未捕获异常也写日志
  runZonedGuarded(
    () => runApp(const MoumouApp()),
    (error, stack) {
      CrashLogService.appendDartLog(
        '━━━ Zone 异常 ${DateTime.now()} ━━━\n$error\n$stack\n━━━━━━━━━━━━━━━━━━━━━━━━',
      );
    },
  );
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
    // 用 ensureLoaded 而非 load：播放页恢复进度时也用 ensureLoaded，
    // 两者共享同一 load Future，防止「main 的 load 未完成、播放页已读
    // 空缓存」的竞态（用户反馈：重启后恢复不了进度的根因）
    PlaybackProgressService.instance.ensureLoaded();
    // 用 ensureLoaded 而非 load：setter 侧的 ensureLoaded 与这里共享同一
    // load Future，防止「启动加载未完成、用户已改设置被 load 覆盖」的竞态
    // （risk_audit #9）
    PlayerControlsSettings.instance.ensureLoaded();
    // 片头片尾设置：同 ensureLoaded 模式（面板 setter 与这里共享同一
    // load Future，防竞态）
    IntroOutroSettings.instance.ensureLoaded();
    // 字幕设置（工作.md 阶段1 第 3 点）：同 ensureLoaded 模式（面板 setter
    // 与这里共享同一 load Future，防竞态）
    SubtitleSettings.instance.ensureLoaded();
    SuperResolutionService.instance.load();
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
