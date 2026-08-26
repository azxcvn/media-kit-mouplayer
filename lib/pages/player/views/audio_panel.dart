import 'package:flutter/material.dart';
import 'package:moumou/models/audio_track.dart';
import 'package:moumou/pages/player/views/subtitle_file_picker.dart';
import 'package:moumou/services/audio_service.dart';
import 'package:moumou/services/device_services.dart';
import 'package:moumou/widgets/player_option_chip.dart';
import 'package:moumou/widgets/player_panel.dart';

/// 音频面板：播放器内「音频」右侧滑入 / 竖屏底部弹出。
///
/// 一级面板直接集成四个板块：
/// - **音轨**：当前可用音频轨道列表（单选：点击选中/再点关闭；外挂轨道带「移除」按钮）；
/// - **导入外部音轨**：外部音轨临时生效（退出播放后不保留）；
/// - **音频声道**：自动 / 安全自动 / 单声道 / 立体声 / 反向立体声（胶囊单选）；
/// - **音频处理**：音量标准化 / 动态范围压缩（胶囊开关）。
///
/// 面板共用 [AudioController]（横竖屏共享同一实例）。声道/音频处理为
/// 会话级状态（每次进播放器重置），直接由 [AudioController] 承载。
///
/// [onPushSubPage]：面板内二级页就地切换回调——横屏页传 [PlayerPanelNavigator]、
/// 竖屏页传 [PlayerBottomPanelNavigator] 的 push（§4.5 约定，页面侧注入）。
class PlayerAudioPanel extends StatelessWidget {
  final AudioController controller;

  /// 面板内二级页推页回调（页面注入，避免面板依赖具体外壳导航器）
  final void Function(String title, Widget body)? onPushSubPage;

  /// 面板内二级页 pop 回调（文件选择器选完/关闭后返回上一级用）
  final VoidCallback? onPopSubPage;

  const PlayerAudioPanel({
    super.key,
    required this.controller,
    this.onPushSubPage,
    this.onPopSubPage,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tracks = controller.tracks;
        final primary = controller.primary;
        // 音频声道两行布局：第一行 3 个短文本、第二行 2 个长文本（等宽均分，
        // 文本不换行，两行总宽度一致、胶囊高度一致）
        const row1 = [
          AudioChannels.auto,
          AudioChannels.mono,
          AudioChannels.stereo,
        ];
        const row2 = [
          AudioChannels.autoSafe,
          AudioChannels.reverseStereo,
        ];
        return ListView(
          key: const PageStorageKey('audio_main'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            // ── 音轨（单选）──────────────────────────────
            const _SectionLabel('音轨'),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '当前视频没有音轨，可在下方导入外部音轨',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              for (final t in tracks)
                _TrackTile(
                  track: t,
                  selected: primary?.id == t.id,
                  onTap: () => controller.cycleSelection(t),
                  onRemove: t.external
                      ? () => controller.removeExternalAudio(t)
                      : null,
                ),
            // ── 外部音轨 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('外部音轨'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_upload_outlined,
                  color: Colors.white, size: 22),
              title: const Text(
                '导入外部音轨',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: const Text(
                '临时生效，退出播放后不保留',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () => _importExternalAudio(context),
            ),
            // ── 音频声道 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('音频声道'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                children: [
                  // 第一行：自动 / 单声道 / 立体声（等宽均分）
                  Row(
                    children: [
                      for (var i = 0; i < row1.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: PlayerOptionChip(
                            label: row1[i].label,
                            selected: controller.channels == row1[i],
                            onTap: () => controller.setChannels(row1[i]),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 第二行：安全自动 / 反向立体声（等宽均分，两行总宽度一致）
                  Row(
                    children: [
                      for (var i = 0; i < row2.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: PlayerOptionChip(
                            label: row2[i].label,
                            selected: controller.channels == row2[i],
                            onTap: () => controller.setChannels(row2[i]),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // ── 音频处理 ────────────────────────────────
            const Divider(height: 1, color: Colors.white12),
            const _SectionLabel('音频处理'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PlayerOptionChip(
                    label: '音量标准化',
                    selected: controller.volumeNormalization,
                    onTap: () => controller.setVolumeNormalization(
                      !controller.volumeNormalization,
                    ),
                  ),
                  PlayerOptionChip(
                    label: '动态范围压缩',
                    selected: controller.drc,
                    onTap: () => controller.setDrc(!controller.drc),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 面板内二级页就地切换（§4.5：复用面板导航器，禁止叠加第二个面板）。
  void _pushSubPage(BuildContext context, String title, Widget body) {
    final push = onPushSubPage;
    if (push != null) {
      push(title, body);
      return;
    }
    // 兑底：无注入时尝试右侧面板导航器（横屏外壳）
    PlayerPanelNavigator.of(context)
        .push(PlayerPanelPage(title: title, body: body));
  }

  /// 导入外部音轨：按 Android 版本走系统/自建文件选择器。
  /// - SDK ≤ 30：系统选择器（原生 ACTION_OPEN_DOCUMENT）；
  /// - SDK ≥ 31：自建选择器（[SubtitleFilePickerPanel] 复用，右侧面板二级页）。
  Future<void> _importExternalAudio(BuildContext context) async {
    final sdk = await DeviceServices.getSdkInt();
    if (!context.mounted || sdk <= 0) return;
    if (sdk <= 30) {
      final path = await AudioFileService.pickWithSystemPicker();
      if (path == null || !context.mounted) return;
      await _importPath(context, path);
      return;
    }
    // 自建选择器：作为右侧面板二级页就地切换（复用字幕文件选择器外壳，
    // 只换文件过滤器/图标/记忆键，对齐 §4.5「不得另写一套面板外壳」）
    _pushSubPage(
      context,
      '选择音频文件',
      SubtitleFilePickerPanel(
        fileFilter: isSupportedAudioFile,
        folderKey: AudioFileService.lastFolderKey,
        fileIcon: Icons.music_note_outlined,
        onPicked: (path) async {
          await controller.addExternalAudio(path);
        },
        onClose: () => onPopSubPage?.call(),
      ),
    );
  }

  /// 导入并给出轻提示（系统选择器路径用；自建选择器返回后由轨道列表刷新体现）
  Future<void> _importPath(BuildContext context, String path) async {
    final ok = await controller.addExternalAudio(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? '已导入外部音轨' : '导入失败，请检查文件格式'),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// 外部音轨文件选择服务（对齐 [SubtitleFileService] 的思路）。
///
/// - SDK ≤ 30：系统选择器（content:// 由原生侧拷贝为真实路径）；
/// - SDK ≥ 31：复用自建选择器（[SubtitleFilePickerPanel]，独立记忆文件夹）。
class AudioFileService {
  AudioFileService._();

  static const lastFolderKey = 'audio_picker_last_folder';

  /// 系统文件选择器（Android ≤ 11）：content:// 拷贝为应用内真实路径后返回。
  static Future<String?> pickWithSystemPicker() async {
    final uri = await DeviceServices.openAudioPicker();
    if (uri == null) return null;
    final name = uri.split('/').where((s) => s.isNotEmpty).last;
    final fileName = name.isEmpty ? 'audio.mp3' : name;
    return DeviceServices.copyAudioFromUri(uri, fileName);
  }
}

/// 音轨行（单选）：统一音量图标，选中态以主题色高亮；
/// 标题只显示干净的轨道名（外挂音轨去掉文件扩展名），外挂/格式/语言用胶囊标签；
/// 移除按钮（垃圾桶）单独放最右。
class _TrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4FC3F7);
    return ListTile(
      dense: true,
      leading: Icon(
        selected
            ? Icons.volume_up_rounded
            : Icons.volume_up_outlined,
        color: selected ? accent : Colors.white54,
        size: 22,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _trackTitle(track),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : Colors.white,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (track.external) const _TrackTag('外挂'),
          if (track.codec != null && track.codec!.trim().isNotEmpty)
            _TrackTag(track.codec!.trim().toUpperCase()),
          if (track.channels != null && track.channels!.trim().isNotEmpty)
            _TrackTag(track.channels!.trim()),
          if (track.language != null &&
              track.language!.trim().isNotEmpty &&
              track.language!.trim() != track.displayTitle)
            _TrackTag(track.language!.trim()),
        ],
      ),
      trailing: onRemove != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 20),
              tooltip: '移除已导入的音轨',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
            )
          : null,
      onTap: onTap,
    );
  }
}

/// 轨道标题：外挂音轨的 title 通常是文件名，去掉扩展名（如 `xxx.m4a` → `xxx`）。
String _trackTitle(AudioTrack track) {
  final t = track.displayTitle;
  if (track.external && isSupportedAudioFile(t)) {
    return t.substring(0, t.lastIndexOf('.'));
  }
  return t;
}

/// 轨道信息胶囊标签（外挂 / 格式 / 声道 / 语言）。
class _TrackTag extends StatelessWidget {
  final String text;

  const _TrackTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      ),
    );
  }
}

/// 面板内小节标题
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
