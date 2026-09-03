import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/pages/bilibili/bili_episode_picker_page.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/widgets/bili_episode_tile.dart';

/// 番剧详情页（对齐 PiliPlus `PgcIntroPage`）：
/// 封面（左下角评分角标）+ 右侧信息（标题 / 播放·弹幕·收藏 / 连载·话数 / 地区·发行
/// / 点赞·投币·收藏）+ 可展开简介 + 多季切换 + 选集（内联前 12 集 + 查看全部）。
///
/// 由 [seasonId]（索引/搜索/时间表入口）或 [epId]（链接解析入口）之一进入。
/// 选集点击提示「播放功能即将上线」（播放属阶段三）。
class BiliSeasonPage extends StatefulWidget {
  final int? seasonId;
  final int? epId;

  const BiliSeasonPage({super.key, this.seasonId, this.epId});

  @override
  State<BiliSeasonPage> createState() => _BiliSeasonPageState();
}

class _BiliSeasonPageState extends State<BiliSeasonPage> {
  final BiliBangumiService _service = BiliBangumiService();

  BiliSeasonDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? seasonId, int? epId}) async {
    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
    });
    try {
      final detail = await _service.fetchSeasonDetail(
        seasonId: seasonId ?? widget.seasonId,
        epId: epId ?? widget.epId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(e);
        _loading = false;
      });
    }
  }

  void _toastComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('播放功能即将上线（阶段三）')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail?.title ?? '番剧详情')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final detail = _detail!;
    final episodes =
        _reverse ? detail.episodes.reversed.toList() : detail.episodes;
    final inlineEpisodes = episodes.take(12).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _Header(detail: detail),
        if (detail.evaluate.isNotEmpty) ...[
          const SizedBox(height: 16),
          _IntroSection(evaluate: detail.evaluate),
        ],
        if (detail.seasons.length > 1) ...[
          const SizedBox(height: 16),
          _SeasonSwitcher(
            seasons: detail.seasons,
            currentId: detail.seasonId,
            onSelect: (id) => _load(seasonId: id),
          ),
        ],
        const SizedBox(height: 16),
        _episodeHeader(context, episodes.length),
        if (episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('暂无选集')),
          )
        else ...[
          _episodeGrid(inlineEpisodes),
          if (episodes.length > 12) ...[
            const SizedBox(height: 10),
            _viewAllButton(episodes),
          ],
        ],
      ],
    );
  }

  /// 内联选集网格（前 12 集，2 列）。
  Widget _episodeGrid(List<BiliEpisode> eps) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 60,
      ),
      itemCount: eps.length,
      itemBuilder: (context, i) => BiliEpisodeTile(
        episode: eps[i],
        onTap: _toastComingSoon,
      ),
    );
  }

  /// 「查看全部」按钮 → 全屏选集页。
  Widget _viewAllButton(List<BiliEpisode> episodes) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BiliEpisodePickerPage(
            episodes: episodes,
            initialReverse: _reverse,
          ),
        ),
      ),
      icon: const Icon(Icons.apps, size: 18),
      label: const Text('查看全部'),
    );
  }

  Widget _episodeHeader(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Text(
          '选集',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(
          '共 $count 集',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => setState(() => _reverse = !_reverse),
          icon: Icon(_reverse ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
          label: Text(_reverse ? '正序' : '倒序'),
        ),
      ],
    );
  }

  static String _errorText(Object e) =>
      e is BiliApiException ? e.message : e.toString();
}

/// 头部：封面（评分角标）+ 右侧信息（标题 / 统计 / 说明）。
class _Header extends StatelessWidget {
  final BiliSeasonDetail detail;
  const _Header({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(context),
        const SizedBox(width: 12),
        Expanded(child: _InfoPanel(detail: detail)),
      ],
    );
  }

  Widget _buildCover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 115,
        height: 153,
        child: Stack(
          fit: StackFit.expand,
          children: [
            detail.cover.isEmpty
                ? ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.live_tv_outlined,
                        color: scheme.onSurfaceVariant, size: 36),
                  )
                : Image.network(
                    detail.cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant, size: 36),
                    ),
                  ),
            if (detail.ratingScore > 0)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '评分 ${detail.ratingScore.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1,
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 右侧信息面板（对齐 PiliPlus `PgcIntroPage` 的行结构）：
/// 标题 → 播放·弹幕 → 连载状态·话数 → 地区·发行时间 → 点赞·投币·收藏。
class _InfoPanel extends StatelessWidget {
  final BiliSeasonDetail detail;
  const _InfoPanel({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 连载状态 + 共多少话：优先 new_ep.desc（如「全13话」「更新至第5话」），
    // 缺失时按选集数量兜底「共 N 集」。
    final statusText = detail.newEpDesc.isNotEmpty
        ? detail.newEpDesc
        : (detail.episodes.isNotEmpty ? '共 ${detail.episodes.length} 集' : '');
    final areaTime = [
      if (detail.areas.isNotEmpty) detail.areas.first,
      if (detail.publishTime.isNotEmpty) detail.publishTime,
    ].join(' · ');
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _statsRow(context, [
          (Icons.play_circle_outline, detail.views),
          (Icons.subtitles_outlined, detail.danmaku),
        ]),
        if (statusText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(statusText, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        ],
        if (areaTime.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(areaTime, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        ],
        const SizedBox(height: 8),
        _statsRow(context, [
          (Icons.thumb_up_outlined, detail.likes),
          (Icons.monetization_on_outlined, detail.coins),
          (Icons.star_border, detail.favorite),
        ]),
      ],
    );
  }

  /// 一行统计（图标 + 数字，等距排列；数字超长时省略号截断，不溢出）。
  Widget _statsRow(BuildContext context, List<(IconData, int)> stats) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Flexible(child: _stat(context, stats[i].$1, stats[i].$2)),
        ],
      ],
    );
  }

  Widget _stat(BuildContext context, IconData icon, int value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            _formatCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  static String _formatCount(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }
}

/// 可展开/收起的简介。
class _IntroSection extends StatefulWidget {
  final String evaluate;
  const _IntroSection({required this.evaluate});

  @override
  State<_IntroSection> createState() => _IntroSectionState();
}

class _IntroSectionState extends State<_IntroSection> {
  bool _expanded = false;

  bool _exceedsLines(double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.evaluate,
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canExpand = _exceedsLines(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '简介',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (canExpand)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起' : '展开'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.evaluate,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, height: 1.6, color: scheme.onSurface),
            ),
          ],
        );
      },
    );
  }
}

/// 多季切换条（横向封面卡片）。
class _SeasonSwitcher extends StatefulWidget {
  final List<BiliSeason> seasons;
  final int currentId;
  final ValueChanged<int> onSelect;

  const _SeasonSwitcher({
    required this.seasons,
    required this.currentId,
    required this.onSelect,
  });

  @override
  State<_SeasonSwitcher> createState() => _SeasonSwitcherState();
}

class _SeasonSwitcherState extends State<_SeasonSwitcher> {
  static const double _itemWidth = 100;
  static const double _separatorWidth = 10;

  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    // 初始滚动到当前选中的季（当前季靠左展示，越界由滚动位置自动钳制）。
    final index = widget.seasons.indexWhere((s) => s.seasonId == widget.currentId);
    final offset = index <= 0 ? 0.0 : index * (_itemWidth + _separatorWidth);
    _controller = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '多季',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 156,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.seasons.length,
            separatorBuilder: (_, _) => const SizedBox(width: _separatorWidth),
            itemBuilder: (context, i) {
              final s = widget.seasons[i];
              final selected = s.seasonId == widget.currentId;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onSelect(s.seasonId),
                child: Container(
                  width: _itemWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(7)),
                          child: SizedBox(
                            width: double.infinity,
                            child: s.cover.isEmpty
                                ? ColoredBox(color: scheme.surfaceContainerHighest)
                                : Image.network(
                                    s.cover,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        ColoredBox(color: scheme.surfaceContainerHighest),
                                  ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          s.seasonTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
