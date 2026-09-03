import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';

/// 番剧单集磁贴（2 列网格用）：集号 + 集名 + 右侧胶囊角标（会员/限免/预告）。
/// 详情页内联选集与全屏选集页共用。
class BiliEpisodeTile extends StatelessWidget {
  final BiliEpisode episode;
  final VoidCallback? onTap;

  const BiliEpisodeTile({super.key, required this.episode, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = episode.title.isNotEmpty
        ? episode.title
        : (episode.epId > 0 ? '第 ${episode.epId} 话' : '');
    final name = _episodeName();
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(10, 8, episode.badge.isNotEmpty ? 42 : 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (episode.badge.isNotEmpty)
              Positioned(
                top: 6,
                right: 6,
                child: _badge(context, episode.badge),
              ),
          ],
        ),
      ),
    );
  }

  /// 集名：`long_title` 去掉与 `title` 重复的前缀（如「第1话 你即将死去」→「你即将死去」）。
  String _episodeName() {
    final lt = episode.longTitle;
    final t = episode.title;
    if (lt.isEmpty) return '';
    if (t.isNotEmpty && lt.startsWith(t)) {
      return lt.substring(t.length).trim();
    }
    return lt;
  }

  /// 胶囊角标：会员→粉色 VIP、限免→绿、预告→灰（浅色底 + 同色文字）。
  Widget _badge(BuildContext context, String badge) {
    final (Color color, String text) = switch (badge) {
      '会员' => (const Color(0xFFFB7299), 'VIP'),
      '限免' => (const Color(0xFF2E9E5B), '限免'),
      '预告' => (Colors.grey, '预告'),
      _ => (Colors.grey, badge),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
