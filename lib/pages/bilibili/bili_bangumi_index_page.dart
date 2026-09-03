import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/pages/bilibili/bili_season_page.dart';
import 'package:moumou/services/bilibili/bili_bangumi_service.dart';
import 'package:moumou/services/bilibili/bili_http.dart';
import 'package:moumou/widgets/bili_cover_card.dart';

/// 番剧索引页（对齐 PiliPlus `PgcIndexPage`）：顶部多行筛选胶囊（排序 + 各维度），
/// 底部封面网格 + 滚动分页。
class BiliBangumiIndexPage extends StatefulWidget {
  const BiliBangumiIndexPage({super.key});

  @override
  State<BiliBangumiIndexPage> createState() => _BiliBangumiIndexPageState();
}

class _BiliBangumiIndexPageState extends State<BiliBangumiIndexPage>
    with SingleTickerProviderStateMixin {
  final BiliBangumiService _service = BiliBangumiService();
  final ScrollController _scroll = ScrollController();

  BiliIndexCondition? _condition;
  Map<String, String> _params = {};
  bool _conditionLoading = true;
  String? _conditionError;
  bool _expanded = false;

  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

  final List<BiliIndexItem> _items = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation =
        CurvedAnimation(parent: _expandController, curve: Curves.easeInOut);
    _scroll.addListener(_onScroll);
    _loadCondition();
  }

  @override
  void dispose() {
    _expandController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadCondition() async {
    setState(() {
      _conditionLoading = true;
      _conditionError = null;
    });
    try {
      final condition = await _service.fetchCondition(1);
      if (!mounted) return;
      final params = <String, String>{};
      if (condition.orders.isNotEmpty) {
        params['order'] = condition.orders.first.field;
      }
      for (final f in condition.filters) {
        if (f.values.isNotEmpty) params[f.field] = f.values.first.keyword;
      }
      setState(() {
        _condition = condition;
        _params = params;
        _conditionLoading = false;
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conditionError = _errorText(e);
        _conditionLoading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _page = 1;
      _hasNext = true;
      _items.clear();
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchIndex(
        seasonType: 1,
        page: 1,
        params: _params,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.list);
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
      final result = await _service.fetchIndex(
        seasonType: 1,
        page: _page + 1,
        params: _params,
      );
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(result.list);
        _hasNext = result.hasNext;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _select(String key, String value) {
    if (_params[key] == value) return;
    setState(() => _params[key] = value);
    _reload();
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('索引')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_conditionLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_conditionError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_conditionError!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadCondition,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final condition = _condition!;
    final rows = _buildFilterRows(condition);
    final collapsedCount = (rows.length ~/ 2).clamp(1, rows.length);
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (rows.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...rows.take(collapsedCount),
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows.skip(collapsedCount).toList(),
                  ),
                ),
                if (rows.length > 5)
                  Center(
                    child: TextButton.icon(
                      onPressed: _toggleExpand,
                      icon: Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                      ),
                      label: Text(_expanded ? '收起' : '展开'),
                    ),
                  ),
              ],
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          sliver: _buildGrid(),
        ),
      ],
    );
  }

  List<Widget> _buildFilterRows(BiliIndexCondition condition) {
    final rows = <Widget>[];
    if (condition.orders.isNotEmpty) {
      rows.add(
        _chipRow([
          for (final o in condition.orders)
            _chip(o.name, _params['order'] == o.field, () => _select('order', o.field)),
        ]),
      );
    }
    for (final f in condition.filters) {
      final values = f.values.where((v) => v.keyword.isNotEmpty).toList();
      if (values.isEmpty) continue;
      rows.add(
        _chipRow([
          for (final v in values)
            _chip(v.name, _params[f.field] == v.keyword, () => _select(f.field, v.keyword)),
        ]),
      );
    }
    return rows;
  }

  Widget _chipRow(List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => chips[i],
        ),
      ),
    );
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading && _items.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _items.isEmpty) {
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
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const SliverFillRemaining(child: Center(child: Text('暂无内容')));
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
          if (i >= _items.length) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final item = _items[i];
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
        childCount: _items.length + (_loading ? 1 : 0),
      ),
    );
  }

  static String _errorText(Object e) =>
      e is BiliApiException ? e.message : e.toString();
}
