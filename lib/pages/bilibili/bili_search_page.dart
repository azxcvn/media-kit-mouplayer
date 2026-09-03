import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/pages/bilibili/bili_season_page.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';

/// 番剧搜索页：顶部搜索框 + 结果列表（media_bangumi 分类，分页加载），
/// 点击结果进入季详情页。
class BiliSearchPage extends StatefulWidget {
  const BiliSearchPage({super.key});

  @override
  State<BiliSearchPage> createState() => _BiliSearchPageState();
}

class _BiliSearchPageState extends State<BiliSearchPage> {
  static const int _pageSize = 20;

  final BiliBangumiService _service = BiliBangumiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String _keyword = '';
  int _page = 1;
  int _numResults = 0;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<BiliSearchItem> _results = [];

  bool get _hasNext => _page * _pageSize < _numResults;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _keyword = kw;
      _page = 1;
      _numResults = 0;
      _results = [];
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      final result = await _service.searchBangumi(kw);
      if (!mounted) return;
      setState(() {
        _results = result.list;
        _numResults = result.numResults;
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
    if (_loading || !_hasNext) return;
    setState(() => _loading = true);
    try {
      final result = await _service.searchBangumi(_keyword, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _results = [..._results, ...result.list];
        _numResults = result.numResults;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: '搜索番剧',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: _search,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return const Center(child: Text('输入关键词搜索番剧'));
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results.isEmpty) {
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
              onPressed: _search,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('没有找到相关番剧'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _results.length + (_loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _SearchItemCard(item: _results[i]);
      },
    );
  }

  static String _errorText(Object e) =>
      e is BiliApiException ? e.message : e.toString();
}

/// 搜索结果条目：封面 + 标题 + 元信息。
class _SearchItemCard extends StatelessWidget {
  final BiliSearchItem item;
  const _SearchItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (item.indexShow.isNotEmpty) item.indexShow,
      if (item.areas.isNotEmpty) item.areas,
      if (item.styles.isNotEmpty) item.styles,
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (item.seasonId <= 0) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BiliSeasonPage(seasonId: item.seasonId),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _cover(context, item.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (item.mediaScore > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star, size: 14, color: scheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          item.mediaScore.toStringAsFixed(1),
                          style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, String cover) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        height: 84,
        child: cover.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.live_tv_outlined, color: scheme.onSurfaceVariant, size: 26),
              )
            : Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant, size: 26),
                ),
              ),
      ),
    );
  }
}
