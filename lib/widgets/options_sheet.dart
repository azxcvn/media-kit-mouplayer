import 'package:flutter/material.dart';
import 'package:moumou/services/view_settings.dart';
import 'package:moumou/utils/app_dialog.dart';

/// 统一的「排序与字段」弹窗（首页 / 目录页 / 详情页共用）。
///
/// - [hasFolders]：是否显示文件夹排序/字段（上半区）
/// - [hasVideos]：是否显示视频排序/字段（下半区）
/// - [showViewMode]：是否显示「显示模式」（仅首页）
///
/// 上半区为文件夹相关（排序方式 → 方向 → 字段），下半区为视频相关，
/// 中间用一条分割线划分；纯文件夹/纯视频时只显示对应半区。
void showSortOptionsSheet(
  BuildContext context,
  ViewSettings viewSettings, {
  required bool hasFolders,
  required bool hasVideos,
  bool showViewMode = false,
}) {
  showAppDialog(
    context: context,
    builder: (context) => _SortOptionsSheet(
      viewSettings: viewSettings,
      hasFolders: hasFolders,
      hasVideos: hasVideos,
      showViewMode: showViewMode,
    ),
  );
}

class _SortOptionsSheet extends StatelessWidget {
  final ViewSettings viewSettings;
  final bool hasFolders;
  final bool hasVideos;
  final bool showViewMode;

  const _SortOptionsSheet({
    required this.viewSettings,
    required this.hasFolders,
    required this.hasVideos,
    required this.showViewMode,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: viewSettings,
          builder: (context, _) {
            final sections = <Widget>[];
            if (hasFolders) {
              // 上半区：文件夹相关
              sections.addAll([
                _sectionTitle(context, '文件夹排序方式'),
                SegmentedButton<SortField>(
                  showSelectedIcon: false,
                  segments: SortField.values
                      .map(
                        (e) => ButtonSegment(value: e, label: Text(e.label)),
                      )
                      .toList(),
                  selected: {viewSettings.sortField},
                  onSelectionChanged: (s) =>
                      viewSettings.setSortField(s.first),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, '文件夹排序方向'),
                SegmentedButton<SortOrder>(
                  showSelectedIcon: false,
                  segments: SortOrder.values
                      .map(
                        (e) => ButtonSegment(value: e, label: Text(e.label)),
                      )
                      .toList(),
                  selected: {viewSettings.sortOrder},
                  onSelectionChanged: (s) =>
                      viewSettings.setSortOrder(s.first),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, '文件夹显示字段'),
                _fieldChips(
                  FolderField.values.map((f) {
                    final selected = viewSettings.fields.contains(f);
                    return (
                      label: f.label,
                      selected: selected,
                      onToggle: () => viewSettings.toggleField(f),
                    );
                  }).toList(),
                ),
              ]);
            }
            if (hasVideos) {
              if (hasFolders) {
                // 混合页面：文件夹区与视频区之间用一条分割线划分
                sections.addAll(const [
                  SizedBox(height: 16),
                  Divider(),
                  SizedBox(height: 16),
                ]);
              }
              // 下半区：视频相关
              sections.addAll([
                _sectionTitle(context, '视频排序方式'),
                SegmentedButton<VideoSortField>(
                  showSelectedIcon: false,
                  segments: VideoSortField.values
                      .map(
                        (e) => ButtonSegment(value: e, label: Text(e.label)),
                      )
                      .toList(),
                  selected: {viewSettings.videoSortField},
                  onSelectionChanged: (s) =>
                      viewSettings.setVideoSortField(s.first),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, '视频排序方向'),
                SegmentedButton<SortOrder>(
                  showSelectedIcon: false,
                  segments: SortOrder.values
                      .map(
                        (e) => ButtonSegment(value: e, label: Text(e.label)),
                      )
                      .toList(),
                  selected: {viewSettings.videoSortOrder},
                  onSelectionChanged: (s) =>
                      viewSettings.setVideoSortOrder(s.first),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, '视频显示字段'),
                _fieldChips(
                  VideoField.values.map((f) {
                    final selected = viewSettings.videoFields.contains(f);
                    return (
                      label: f.label,
                      selected: selected,
                      onToggle: () => viewSettings.toggleVideoField(f),
                    );
                  }).toList(),
                ),
              ]);
            }
            if (showViewMode) {
              sections.addAll(const [
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
              ]);
              sections.addAll([
                _sectionTitle(context, '显示模式'),
                SegmentedButton<ViewMode>(
                  showSelectedIcon: false,
                  // 列表模式在前、树状模式在后
                  segments: [ViewMode.list, ViewMode.tree]
                      .map(
                        (e) => ButtonSegment(value: e, label: Text(e.label)),
                      )
                      .toList(),
                  selected: {viewSettings.viewMode},
                  onSelectionChanged: (s) =>
                      viewSettings.setViewMode(s.first),
                ),
              ]);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('排序与字段', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ...sections,
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fieldChips(
    List<({String label, bool selected, VoidCallback onToggle})> items,
  ) {
    return Align(
      alignment: Alignment.center,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: items
            .map(
              (e) => FilterChip(
                label: Text(e.label),
                selected: e.selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => e.onToggle(),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
