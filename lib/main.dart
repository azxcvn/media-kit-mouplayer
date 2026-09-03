import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moumou/models/danmaku_font_mode.dart';
import 'package:moumou/pages/home/home_page.dart';
import 'package:moumou/pages/settings/settings_page.dart';
import 'package:moumou/services/app_font_settings.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/crash_log_service.dart';
import 'package:moumou/services/danmaku_server_settings.dart';
import 'package:moumou/services/danmaku_settings.dart';
import 'package:moumou/services/decode_settings.dart';
import 'package:moumou/services/equalizer_settings.dart';
import 'package:moumou/services/intro_outro_settings.dart';
import 'package:moumou/services/media_scan_settings.dart';
import 'package:moumou/services/network/network_connection_settings.dart';
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

Future<void> main() async {
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
  // 自定义字体必须在 runApp 前注册进引擎（loadFontFromList 只对当前进程有效，
  // 首次渲染该 family 前未注册会回落默认字体）。App 全局字体 + 弹幕自定义字体
  // 各注册一次（见 §4.12）。
  await AppFontSettings.instance.ensureLoaded();
  await AppFontSettings.instance.registerCurrentFont();
  await DanmakuSettings.instance.ensureLoaded();
  await _registerDanmakuFont();
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

/// 冷启动注册弹幕「自定义」字体（仅 custom 模式且已选字体时）。
Future<void> _registerDanmakuFont() async {
  final s = DanmakuSettings.instance;
  if (s.fontMode == DanmakuFontMode.custom &&
      s.customFontFamily != null &&
      s.customFontFile != null) {
    await AppFontSettings.registerFontFile(
      s.customFontFamily!,
      s.customFontFile!,
    );
  }
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
    // 媒体扫描设置：同 ensureLoaded 模式
    MediaScanSettings.instance.ensureLoaded();
    SuperResolutionService.instance.load();
    // 解码设置（硬解/软解档位）：同 ensureLoaded 模式，播放页创建
    // VideoController 时同步读取（防竞态）
    DecodeSettings.instance.ensureLoaded();
    // 音频均衡器设置（工作.md 均衡器功能）：同 ensureLoaded 模式，
    // AudioController 构造时订阅、applyAudioOptions 读取（防竞态）
    EqualizerSettings.instance.ensureLoaded();
    // 弹幕设置（阶段2）：同 ensureLoaded 模式，DanmakuController 构造时
    // 订阅并读取（面板 setter 与这里共享同一 load Future，防竞态）
    DanmakuSettings.instance.ensureLoaded();
    // 弹幕服务器设置（阶段3 网络弹幕）：同 ensureLoaded 模式，切集自动匹配
    // 与网络搜索读取服务器列表/开关（setter 与这里共享同一 load Future）
    DanmakuServerSettings.instance.ensureLoaded();
    // 网络存储账户（阶段4 网络存储）：同 ensureLoaded 模式，账户列表页
    // ListenableBuilder 订阅、账户增删改用 setter 与这里共享同一 load Future
    NetworkConnectionSettings.instance.ensureLoaded();
    // App 全局字体设置（工作.md 第 3 点）：同 ensureLoaded 模式；main() 已在
    // runApp 前 await 注册，这里补 ensureLoaded 防测试/热重载路径竞态
    AppFontSettings.instance.ensureLoaded();
    // 哔哩哔哩账号（工作.md 阶段一）：启动读凭证 + nav 自检（含 buvid 预取），
    // 异步执行不阻塞首帧；「我的」页监听其 ChangeNotifier 实时刷新登录态
    BiliAccount.instance.ensureLoaded();
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
      listenable: Listenable.merge([_themeController, AppFontSettings.instance]),
      builder: (context, _) {
        final seed = _themeController.seedColor;
        final mode = _themeController.mode;
        final variant = _themeController.variant;
        final fontFamily = AppFontSettings.instance.effectiveFamily;
        final fontWeight = AppFontSettings.instance.effectiveFontWeight;

        final light = AppTheme.light(
          seed,
          variant,
          fontFamily: fontFamily,
          fontWeight: fontWeight,
        );
        // AMOLED 模式下深色主题换成纯黑版本
        final dark = mode == AppThemeMode.amoled
            ? AppTheme.amoled(
                seed,
                variant,
                fontFamily: fontFamily,
                fontWeight: fontWeight,
              )
            : AppTheme.dark(
                seed,
                variant,
                fontFamily: fontFamily,
                fontWeight: fontWeight,
              );
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
          // 全局框架：安全区 + 播放页全屏（详见 AppFrame）；
          // App 自定义字体启用时叠加整体字号缩放（仅 Flutter Text）
          builder: (context, child) {
            final scale = AppFontSettings.instance.effectiveTextScale;
            if ((scale - 1.0).abs() < 0.0001) {
              return AppFrame(child: child!);
            }
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: AppFrame(child: child!),
            );
          },
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
                // 「我的」页：账号 + 设置（对齐手机系统设置的信息架构），
                // 图标用联系人头像样式占位（登录后可换成用户头像）
                icon: Icons.account_circle_outlined,
                label: '我的',
                page: SettingsPage(controller: _themeController),
              ),
            ],
          ),
        );
      },
    );
  }
}
