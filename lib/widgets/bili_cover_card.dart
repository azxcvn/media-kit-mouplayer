import 'package:flutter/material.dart';

/// 哔哩番剧封面卡片（对齐 PiliPlus `PgcCardV` 系列）：竖版封面（3:4）+
/// 右上角标 + 左下角灰标 + 标题 + 副标题。索引网格 / 推荐网格 / 追番时间表共用。
///
/// 卡片放在固定高度的网格单元里（封面用 [Expanded] 占满剩余高度），
/// 网格用 `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160,
/// childAspectRatio: 0.58)` 之类即可得到近似 3:4 封面。
class BiliCoverCard extends StatelessWidget {
  final String cover;
  final String? badge; // 右上角标（主题色，如「独播」「会员」）
  final String? cornerText; // 左下角灰标（如「更新至第5话」「19:00」）
  final String title;
  final String? subtitle; // 标题下方小字（如「全13话」「第5话」）
  final VoidCallback? onTap;

  const BiliCoverCard({
    super.key,
    required this.cover,
    required this.title,
    this.badge,
    this.cornerText,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _coverImage(context, cover),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Tag(
                        text: badge!,
                        color: scheme.primary,
                        textColor: scheme.onPrimary,
                      ),
                    ),
                  if (cornerText != null && cornerText!.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: _Tag(text: cornerText!, color: Colors.black45),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 2, 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  // 副标题行始终占位（无副标题时用空白占位），保证封面高度一致。
                  const SizedBox(height: 1),
                  Text(
                    (subtitle != null && subtitle!.isNotEmpty) ? subtitle! : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverImage(BuildContext context, String cover) {
    final scheme = Theme.of(context).colorScheme;
    if (cover.isEmpty) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.live_tv_outlined, color: scheme.onSurfaceVariant, size: 28),
      );
    }
    return Image.network(
      cover,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant, size: 28),
      ),
    );
  }
}

/// 封面角标胶囊（小圆角 + 白字）。
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;

  const _Tag({required this.text, required this.color, this.textColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
