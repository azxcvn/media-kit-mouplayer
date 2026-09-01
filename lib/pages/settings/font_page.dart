import 'package:flutter/material.dart';
import 'package:moumou/services/app_font_settings.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/widgets/settings_ui.dart';
import 'package:path/path.dart' as p;

/// App 字体设置页（工作.md 第 3 点）：
/// - 顶部「启用自定义字体」开关（关闭 = 跟随系统字体）；
/// - 启用后展开：字体预览（数字+符号一行 / 大写 / 小写 / 中文，统一字号）
///   + 导入字体（系统文件选择器）+ 字号/字重滑杆 + 一键重置。
///
/// 导入走系统文件选择器（ACTION_OPEN_DOCUMENT，MIME font/*）选单个字体，
/// 拷贝到 filesDir/fonts/ 后解析族名并 `loadFontFromList` 注册（§4.12）。
class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage({super.key});

  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<FontSettingsPage> {
  bool _importing = false;

  /// 字体字重档位名（w100~w900，对齐弹幕字重滑杆）
  static const List<String> _weightNames = [
    '极细',
    '很细',
    '细',
    '常规',
    '中等',
    '较粗',
    '粗',
    '很粗',
    '极粗',
  ];

  static String _weightLabel(int index) =>
      index < 0 ? '默认' : _weightNames[index];

  Future<void> _pickFont() async {
    final uri = await DeviceServices.openFontPicker();
    if (uri == null || !mounted) return;
    setState(() => _importing = true);
    final path = await DeviceServices.copyFontFromUri(uri, 'custom_font.ttf');
    if (path == null || !mounted) {
      if (mounted) setState(() => _importing = false);
      return;
    }
    final family = await DeviceServices.getFontFamilyName(path);
    if (!mounted) return;
    setState(() => _importing = false);
    if (family.isEmpty) {
      _toast('字体解析失败，请更换字体文件');
      return;
    }
    await AppFontSettings.instance.setFont(family, p.basename(path));
    if (!mounted) return;
    _toast('已应用字体：$family');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('App字体设置')),
      body: ListenableBuilder(
        listenable: AppFontSettings.instance,
        builder: (context, _) {
          final s = AppFontSettings.instance;
          final enabled = s.enabled;
          final hasFont = s.family != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              // ── 开关（最上方）────────────────────────
              SettingsCard(
                child: SettingsSwitchTile(
                  icon: Icons.font_download_outlined,
                  title: '启用自定义字体',
                  subtitle: Text(
                    enabled ? '已开启：使用下方导入的字体' : '已关闭：跟随系统字体',
                  ),
                  value: enabled,
                  onChanged: (v) => AppFontSettings.instance.setEnabled(v),
                ),
              ),
              if (enabled) ...[
                const SizedBox(height: 20),
                // ── 预览（数字+符号一行 / 大写 / 小写 / 中文，统一字号）──
                SettingsCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 数字与符号合并为一行，缩小字距
                      _PreviewText(
                        '0123456789，。！？；：“”（）【】…·',
                        fontSize: 12,
                        letterSpacing: -0.5,
                      ),
                      const SizedBox(height: 4),
                      _PreviewText(
                        'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                        fontSize: 12,
                        weight: FontWeight.w600,
                      ),
                      const SizedBox(height: 4),
                      _PreviewText(
                        'abcdefghijklmnopqrstuvwxyz',
                        fontSize: 12,
                      ),
                      const SizedBox(height: 4),
                      _PreviewText(
                        '生如夏花之绚烂，死如秋叶之静美。\n'
                        '我把你的名字写在树叶上，风把它吹走了；\n'
                        '我把你的名字写在沙滩上，浪把它冲走了；',
                        fontSize: 12,
                        height: 1.6,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '部分字体可能不生效',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SettingsGroupTitle(title: '字体'),
                SettingsCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      if (hasFont) ...[
                        _FontSlider(
                          label: '字体字号',
                          display: '${s.textScale.toStringAsFixed(2)}x',
                          value: s.textScale,
                          min: AppFontSettings.minTextScale,
                          max: AppFontSettings.maxTextScale,
                          onChanged: (v) => s.setTextScale(v),
                        ),
                        const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                        _FontSlider(
                          label: '字体字重',
                          display: _weightLabel(s.fontWeightIndex),
                          value: s.fontWeightIndex.toDouble(),
                          min: -1,
                          max: 8,
                          divisions: 9,
                          onChanged: (v) => s.setFontWeightIndex(v.round()),
                        ),
                        const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                      ],
                      // 导入字体放在字重下方：拖动滑杆时无需上下滑动即可换字体
                      SettingsTile(
                        icon: Icons.upload_file_outlined,
                        title: _importing ? '正在导入...' : '导入字体',
                        subtitle: Text(
                          hasFont
                              ? '当前字体：${s.family}'
                              : '点击选择 .ttf/.otf 字体文件',
                        ),
                        trailing: hasFont
                            ? IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Colors.grey,
                                ),
                                tooltip: '重新选择',
                                onPressed: _importing ? null : _pickFont,
                              )
                            : null,
                        onTap: _importing ? null : _pickFont,
                      ),
                      if (hasFont) ...[
                        const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: TextButton.icon(
                              onPressed: () async {
                                await s.setTextScale(1.0);
                                await s.setFontWeightIndex(-1);
                              },
                              icon: const Icon(Icons.restart_alt, size: 16),
                              label: const Text('重置字号与字重'),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 预览文本行（继承全局 fontFamily，即当前生效字体）
class _PreviewText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight weight;
  final double? height;
  final double? letterSpacing;

  const _PreviewText(
    this.text, {
    required this.fontSize,
    this.weight = FontWeight.w400,
    this.height,
    this.letterSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// 设置页滑杆行（Kazumi 外观 + 右侧实时读数，改动实时写设置）
class _FontSlider extends StatelessWidget {
  final String label;
  final String display;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _FontSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                display,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: kazumiSliderTheme(scheme),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
