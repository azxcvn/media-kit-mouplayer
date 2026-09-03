import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:moumou/models/bili_bangumi.dart';
import 'package:moumou/widgets/bili_episode_tile.dart';

/// 全屏选集页：按 30 集一段分段（「1-30」「31-60」…）+ 2 列网格（集号 + 集名 +
/// 角标）+ 正序/倒序。点击选集提示「播放即将上线」（播放属阶段三）。
class BiliEpisodePickerPage extends StatefulWidget {
  final List<BiliEpisode> episodes;
  final bool initialReverse;

  const BiliEpisodePickerPage({
    super.key,
    required this.episodes,
    this.initialReverse = false,
  });

  @override
  State<BiliEpisodePickerPage> createState() => _BiliEpisodePickerPageState();
}

class _BiliEpisodePickerPageState extends State<BiliEpisodePickerPage> {
  static const int _pageSize = 30;

  late bool _reverse = widget.initialReverse;
  int _page = 0;

  List<BiliEpisode> get _ordered =>
      _reverse ? widget.episodes.reversed.toList() : widget.episodes;

  int get _pageCount => (_ordered.length / _pageSize).ceil();

  List<BiliEpisode> get _currentPage =>
      _ordered.skip(_page * _pageSize).take(_pageSize).toList();

  void _toggleReverse() {
    setState(() {
      _reverse = !_reverse;
      _page = 0;
    });
  }

  void _toastComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('播放功能即将上线（阶段三）')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选集'),
        actions: [
          TextButton.icon(
            onPressed: _toggleReverse,
            icon: Icon(_reverse ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
            label: Text(_reverse ? '正序' : '倒序'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pageCount > 1) _buildPageSelector(),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildPageSelector() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _pageCount,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final start = i * _pageSize + 1;
          final end = math.min((i + 1) * _pageSize, _ordered.length);
          final selected = _page == i;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _page = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$start-$end',
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 60,
      ),
      itemCount: _currentPage.length,
      itemBuilder: (context, i) => BiliEpisodeTile(
        episode: _currentPage[i],
        onTap: _toastComingSoon,
      ),
    );
  }
}
