import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/pages/bilibili/bili_bangumi_index_page.dart';
import 'package:moumou/pages/bilibili/bili_play_launcher.dart';
import 'package:moumou/pages/bilibili/bili_search_page.dart';
import 'package:moumou/pages/bilibili/bili_season_page.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/utils/app_dialog.dart';
import 'package:moumou/utils/bili_bangumi_url.dart';
import 'package:moumou/utils/bili_short_link.dart';
import 'package:moumou/widgets/bili_cover_card.dart';

/// 哔哩番剧首页（对齐 PiliPlus `PgcPage`）：顶部「追番时间表」+ 底部「推荐」网格。
/// 右上角「链接解析 / 搜索」；「推荐」标题右侧「索引」进入番剧索引页。
class BiliIndexPage extends StatefulWidget {
  const BiliIndexPage({super.key});

  @override
  State<BiliIndexPage> createState() => _BiliIndexPageState();
}

class _BiliIndexPageState extends State<BiliIndexPage> {
  final BiliBangumiService _service = BiliBangumiService();
  final ScrollController _scroll = ScrollController();

  final List<BiliIndexItem> _recommend = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadRecommend();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadRecommend() async {
    setState(() {
      _page = 1;
      _hasNext = true;
      _recommend.clear();
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchRecommend(1);
      if (!mounted) return;
      setState(() {
        _recommend.addAll(result.list);
        _hasNext = result.hasNext;
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

  Future<void> _loadMore() async {
    if (_loading || !_hasNext || _error != null) return;
    setState(() => _loading = true);
    try {
      final result = await _service.fetchRecommend(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _recommend.addAll(result.list);
        _hasNext = result.hasNext;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openIndex() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BiliBangumiIndexPage()),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BiliSearchPage()),
    );
  }

  Future<void> _openLinkParse() async {
    final ref = await showAppDialog<BiliBangumiRef>(
      context: context,
      builder: (_) => const _LinkParseDialog(),
    );
    if (ref == null || !mounted || !ref.isValid) return;
    if (ref.isUgc) {
      await playBiliBvid(context, ref.bvid);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BiliSeasonPage(
          seasonId: ref.hasSeason ? ref.seasonId : null,
          epId: ref.hasEpisode ? ref.epId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('哔哩番剧'),
        actions: [
          IconButton(
            tooltip: '解析链接',
            icon: const Icon(Icons.link),
            onPressed: _openLinkParse,
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommend,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _TimelineSection()),
            SliverToBoxAdapter(child: _buildRecommendHeader(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              sliver: _buildRecommendGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '推荐',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          TextButton.icon(
            onPressed: _openIndex,
            icon: Icon(Icons.tune, size: 16, color: scheme.primary),
            label: Text(
              '索引',
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendGrid() {
    if (_loading && _recommend.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _recommend.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadRecommend,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.58,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i >= _recommend.length) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final item = _recommend[i];
          return BiliCoverCard(
            cover: item.cover,
            title: item.title,
            badge: item.badge,
            cornerText: item.order,
            subtitle: item.indexShow,
            onTap: item.seasonId > 0
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BiliSeasonPage(seasonId: item.seasonId),
                      ),
                    )
                : null,
          );
        },
        childCount: _recommend.length + (_loading ? 1 : 0),
      ),
    );
  }

  static String _errorText(Object e) =>
      e is BiliApiException ? e.message : e.toString();
}

/// 追番时间表：日期 Tab + 横向选集卡片（番剧 + 国创两条时间线合并）。
class _TimelineSection extends StatefulWidget {
  const _TimelineSection();

  @override
  State<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<_TimelineSection> {
  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];

  final BiliBangumiService _service = BiliBangumiService();
  List<BiliTimelineDay> _days = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _weekLabel(BiliTimelineDay d) {
    final i = d.dayOfWeek - 1;
    return (i >= 0 && i < _week.length) ? '周${_week[i]}' : '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final days = await _service.fetchTimelineMerged();
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (_) {
      // 时间表失败静默隐藏（不阻断推荐列表）
      if (!mounted) return;
      setState(() {
        _days = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_days.isEmpty) return const SizedBox.shrink();
    final todayIndex = _days.indexWhere((d) => d.isToday);
    final initialIndex = todayIndex < 0 ? 0 : todayIndex;
    return DefaultTabController(
      initialIndex: initialIndex,
      length: _days.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text(
                  '追番时间表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerHeight: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              labelColor: Theme.of(context).colorScheme.onSecondaryContainer,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: [
                for (final d in _days)
                  Tab(text: '${d.date} ${d.isToday ? '今天' : _weekLabel(d)}'),
              ],
            ),
          ),
          SizedBox(
            height: 190,
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final d in _days)
                  d.episodes.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                          itemCount: d.episodes.length,
                          itemBuilder: (context, i) {
                            final ep = d.episodes[i];
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: SizedBox(
                                width: 110,
                                child: BiliCoverCard(
                                  cover: ep.cover,
                                  title: ep.title,
                                  badge: ep.follow == 1 ? '已追番' : null,
                                  cornerText: ep.pubTime,
                                  subtitle: ep.pubIndex,
                                  onTap: ep.seasonId > 0
                                      ? () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => BiliSeasonPage(
                                                seasonId: ep.seasonId,
                                                epId: ep.episodeId,
                                              ),
                                            ),
                                          )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 链接解析弹窗：粘贴链接 → 提取 ss/ep/BV → 返回引用。
class _LinkParseDialog extends StatefulWidget {
  const _LinkParseDialog();

  @override
  State<_LinkParseDialog> createState() => _LinkParseDialogState();
}

class _LinkParseDialogState extends State<_LinkParseDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _resolving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_resolving) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    var ref = parseBiliBangumiUrl(text);
    if (ref == null) {
      // b23.tv 等分享短链不含令牌，先展开再解析
      setState(() {
        _resolving = true;
        _error = null;
      });
      final expanded = await expandBiliShortLink(
        text,
        isTarget: (url) => parseBiliBangumiUrl(url) != null,
      );
      if (!mounted) return;
      setState(() => _resolving = false);
      if (expanded != null) ref = parseBiliBangumiUrl(expanded);
    }
    if (!mounted || ref == null || !ref.isValid) {
      setState(() => _error = '无法识别该链接（支持 ss/ep/BV/av 号与 b23.tv 短链）');
      return;
    }
    Navigator.of(context).pop(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '解析番剧链接',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '粘贴番剧/视频链接或 b23.tv 短链',
                errorText: _error,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _resolving ? null : _submit,
                  child: _resolving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('解析'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
