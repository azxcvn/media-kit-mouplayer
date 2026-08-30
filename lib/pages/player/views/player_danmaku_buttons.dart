/// 弹幕开关 + 弹幕设置按钮组（横竖屏播放页底栏共用）。
///
/// 图标取自 Kazumi（工作.md 弹幕第 4 点）：
/// - 开启：内联 SVG 常量 [kDanmakuOnSvg]（Kazumi `constants.dart` 的
///   `danmakuOnSvg` 原样移植）——主体白色 + 对勾 `#00AEEC`，运行时把
///   对勾色替换为主题色（与 Kazumi 同款动态换色）；
/// - 关闭：`assets/icons/danmaku_off.svg`（文件资源）；
/// - 设置：`assets/icons/danmaku_setting.svg`（文件资源）。
///
/// 按钮为纯图标无背景样式（与底栏列表按钮一致）；SVG 组件按
/// 「图标态 + 主题色 + 尺寸」缓存，避免底栏随位置流高频重建时反复解析。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:moumou/pages/player/views/player_pressable.dart';

/// 弹幕开启图标（带对勾；对勾色 `#00AEEC` 运行时替换为主题色）。
const String kDanmakuOnSvg = '''
    <svg xmlns="http://www.w3.org/2000/svg" data-pointer="none" viewBox="0 0 24 24">
      <path fill="#FFFFFF" fill-rule="evenodd" d="M11.989 4.828c-.47 0-.975.004-1.515.012l-1.71-2.566a1.008 1.008 0 0 0-1.678 1.118l.999 1.5c-.681.018-1.403.04-2.164.068a4.013 4.013 0 0 0-3.83 3.44c-.165 1.15-.245 2.545-.245 4.185 0 1.965.115 3.67.35 5.116a4.012 4.012 0 0 0 3.763 3.363l.906.046c1.205.063 1.808.095 3.607.095a.988.988 0 0 0 0-1.975c-1.758 0-2.339-.03-3.501-.092l-.915-.047a2.037 2.037 0 0 1-1.91-1.708c-.216-1.324-.325-2.924-.325-4.798 0-1.563.076-2.864.225-3.904.14-.977.96-1.713 1.945-1.747 2.444-.087 4.465-.13 6.063-.131 1.598 0 3.62.044 6.064.13.96.034 1.71.81 1.855 1.814.075.524.113 1.962.141 3.065v.002c.01.342.017.65.025.88a.987.987 0 1 0 1.974-.068c-.008-.226-.016-.523-.025-.856v-.027c-.03-1.118-.073-2.663-.16-3.276-.273-1.906-1.783-3.438-3.74-3.507-.9-.032-1.743-.058-2.531-.078l1.05-1.46a1.008 1.008 0 0 0-1.638-1.177l-1.862 2.59c-.38-.004-.744-.007-1.088-.007h-.13Zm.521 4.775h-1.32v4.631h2.222v.847h-2.618v1.078h2.618l.003.678c.36.026.714.163 1.01.407h.11v-1.085h2.694v-1.078h-2.695v-.847H16.8v-4.63h-1.276a8.59 8.59 0 0 0 .748-1.42L15.183 7.8a14.232 14.232 0 0 1-.814 1.804h-1.518l.693-.308a8.862 8.862 0 0 0-.814-1.408l-1.045.352c.297.396.572.847.825 1.364Zm-4.18 3.564.154-1.485h1.98V8.294h-3.2v.98H9.33v1.43H7.472l-.308 3.453h2.277c0 1.166-.044 1.925-.12 2.277-.078.352-.386.528-.936.528-.308 0-.616-.022-.902-.055l.297 1.067.062.005c.285.02.551.04.818.04 1.001-.067 1.562-.419 1.694-1.057.11-.638.176-1.903.176-3.795h-2.2Zm7.458.11v-.858h-1.254v.858h1.254Zm-2.376-.858v.858h-1.199v-.858h1.2Zm-1.199-.946h1.2v-.902h-1.2v.902Zm2.321 0v-.902h1.254v.902h-1.254Z" clip-rule="evenodd"/>
      <path fill="#00AEEC" fill-rule="evenodd" d="M22.846 14.627a1 1 0 0 0-1.412.075l-5.091 5.703-2.216-2.275-.097-.086-.008-.005a1 1 0 0 0-1.322 1.493l2.963 3.041.093.083.007.005a1 1 0 0 0 1.354-.124l5.81-6.505.08-.102.005-.008a1 1 0 0 0-.166-1.295Z" clip-rule="evenodd"/>
    </svg>
    ''';

/// SVG 图标缓存（key = 图标态 + 主题色 + 尺寸）：底栏随位置流高频重建，
/// 缓存后零重复解析
final Map<String, Widget> _svgIconCache = {};

Widget _cachedSvg(String key, Widget Function() builder) =>
    _svgIconCache[key] ??= RepaintBoundary(child: builder());

class PlayerDanmakuButtons extends StatelessWidget {
  /// 弹幕是否开启（决定开关图标：开 = 带对勾 + 主题色，关 = 斜杠圆环）
  final bool danmakuOn;

  /// 点击弹幕开关（显示 ⇄ 隐藏）
  final VoidCallback onToggle;

  /// 点击弹幕设置
  final VoidCallback onSettings;

  /// 图标边长（横屏底栏 22，对齐其他图标；竖屏 20）
  final double iconSize;

  /// 两按钮间距（与所在底栏右侧按钮簇的按钮间距一致：横屏 8 / 竖屏 6）
  final double gap;

  /// 按钮内边距（触摸目标；横竖屏与所在底栏图标按钮一致）
  final EdgeInsetsGeometry buttonPadding;

  const PlayerDanmakuButtons({
    super.key,
    required this.danmakuOn,
    required this.onToggle,
    required this.onSettings,
    this.iconSize = 22,
    this.gap = 8,
    this.buttonPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DanmakuIconButton(
          tooltip: danmakuOn ? '关闭弹幕' : '打开弹幕',
          padding: buttonPadding,
          onTap: onToggle,
          icon: _toggleIcon(context),
        ),
        SizedBox(width: gap),
        _DanmakuIconButton(
          tooltip: '弹幕设置',
          padding: buttonPadding,
          onTap: onSettings,
          icon: _cachedSvg(
            'setting-$iconSize',
            () => SvgPicture.asset(
              'assets/icons/danmaku_setting.svg',
              height: iconSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleIcon(BuildContext context) {
    if (!danmakuOn) {
      return _cachedSvg(
        'off-$iconSize',
        () => SvgPicture.asset(
          'assets/icons/danmaku_off.svg',
          height: iconSize,
        ),
      );
    }
    // 对勾色替换为当前主题色（Kazumi 同款：运行时把 #00AEEC 换成
    // colorScheme.primary；padLeft 保证 ARGB 十六进制满 8 位再去 alpha）
    final colorHex = Theme.of(context)
        .colorScheme
        .primary
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2);
    return _cachedSvg(
      'on-$colorHex-$iconSize',
      () => SvgPicture.string(
        kDanmakuOnSvg.replaceFirst('00AEEC', colorHex),
        height: iconSize,
      ),
    );
  }
}

/// 弹幕图标按钮：纯图标无背景（与底栏列表按钮同款样式），带 Tooltip
/// 与按压缩放反馈（[PlayerPressable]）。
class _DanmakuIconButton extends StatelessWidget {
  final String tooltip;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;
  final Widget icon;

  const _DanmakuIconButton({
    required this.tooltip,
    required this.padding,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerPressable(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Padding(padding: padding, child: icon),
      ),
    );
  }
}
