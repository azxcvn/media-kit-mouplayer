import 'package:flutter/material.dart';
import 'package:moumou/models/bili_dash.dart';
import 'package:moumou/pages/download/download_manager_page.dart';
import 'package:moumou/services/bilibili/bili_download_service.dart';
import 'package:moumou/services/download/download_manager.dart';
import 'package:moumou/services/download/download_settings.dart';
import 'package:moumou/services/download/download_task.dart';
import 'package:moumou/widgets/directory_picker_dialog.dart';

/// 哔哩哔哩视频下载页。
///
/// 顶部：链接输入框 + 「解析」按钮。解析前强制设置下载目录；解析后展示
/// 番剧（多集）/ 视频（多分 P）列表，支持**清晰度选择**（老项目缺失的能力）、
/// 逐集/分 P 勾选与全选，以及「同步下载弹幕」开关。点「下载」为每个勾选项
/// 创建一条视频下载任务入队。
class BiliVideoDownloadPage extends StatefulWidget {
  const BiliVideoDownloadPage({super.key});

  @override
  State<BiliVideoDownloadPage> createState() => _BiliVideoDownloadPageState();
}

class _BiliVideoDownloadPageState extends State<BiliVideoDownloadPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final BiliDownloadService _service = BiliDownloadService();

  bool _busy = false;
  BiliDownloadTarget? _target;
  final Set<int> _selected = {};
  String? _error;

  List<BiliQualityOption> _qualities = [];
  int _qn = 0;
  bool _withDanmaku = true;

  @override
  void initState() {
    super.initState();
    DownloadSettings.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final picked = await showDirectoryPickerDialog(context);
    if (picked != null) {
      await DownloadSettings.instance.setDirectory(picked);
      if (mounted) setState(() {});
    }
  }

  Future<void> _parse() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!DownloadSettings.instance.hasDirectory) {
      _toast('请先设置下载目录');
      await _pickDir();
      if (!DownloadSettings.instance.hasDirectory) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _target = null;
      _selected.clear();
      _qualities = [];
      _qn = 0;
    });
    try {
      final target = await _service.resolve(url);
      final qualities = await _service.fetchQualityOptions(target);
      if (!mounted) return;
      setState(() {
        _target = target;
        _qualities = qualities;
        _qn = _defaultQn(qualities);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final target = _target;
    if (target == null || _selected.isEmpty) return;
    final dir = DownloadSettings.instance.directory;
    var i = 0;
    for (final idx in _selected.toList()..sort()) {
      final item = target.items[idx];
      DownloadManager.instance.enqueue(
        DownloadTask(
          id: 'vd_${DateTime.now().microsecondsSinceEpoch}_${i++}',
          title: item.title,
          subtitle: target.title,
          coverUrl: target.cover,
          isVideo: true,
          saveDir: dir,
          aid: item.aid,
          cid: item.cid,
          epId: item.epId,
          seasonId: item.seasonId,
          bvid: item.bvid,
          qn: _qn,
          withDanmaku: _withDanmaku,
        ),
      );
    }
    if (!mounted) return;
    _toast('已添加 ${_selected.length} 个视频下载任务');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadManagerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('视频下载')),
      body: Column(
        children: [
          _buildInput(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              onSubmitted: (_) => _parse(),
              decoration: InputDecoration(
                hintText: '粘贴 B 站视频/番剧链接（BV / ss / ep）',
                isDense: true,
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _parse,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('解析'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final target = _target;
    if (target == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dirTile(),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '粘贴链接后点「解析」',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _dirTile(),
        _headerBar(),
        if (_qualities.isNotEmpty) _qualityBar(),
        _selectAllBar(),
        Expanded(
          child: ListView.builder(
            itemCount: target.items.length,
            itemBuilder: (_, i) {
              final item = target.items[i];
              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(i),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(i);
                  } else {
                    _selected.remove(i);
                  }
                }),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              );
            },
          ),
        ),
        _downloadBar(),
      ],
    );
  }

  Widget _dirTile() {
    final scheme = Theme.of(context).colorScheme;
    final dir = DownloadSettings.instance.directory;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        dir.isEmpty ? '未设置下载目录' : DownloadSettings.instance.directoryName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      ),
      trailing: TextButton(onPressed: _pickDir, child: const Text('设置目录')),
    );
  }

  Widget _qualityBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              '清晰度',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final q in _qualities) ...[
                    ChoiceChip(
                      label: Text(q.description),
                      labelStyle: const TextStyle(fontSize: 12),
                      selected: _qn == q.qn,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _qn = q.qn),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBar() {
    final target = _target!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              target.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const Text('同步弹幕', style: TextStyle(fontSize: 12)),
          Switch(
            value: _withDanmaku,
            onChanged: (v) => setState(() => _withDanmaku = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _selectAllBar() {
    final target = _target!;
    final all = _selected.length == target.items.length && target.items.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Checkbox(
            value: all,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.addAll(List.generate(target.items.length, (i) => i));
              } else {
                _selected.clear();
              }
            }),
          ),
          const Text('全选'),
          const Spacer(),
          Text('已选 ${_selected.length} / 共 ${target.items.length} 集'),
        ],
      ),
    );
  }

  Widget _downloadBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _download,
            icon: const Icon(Icons.download),
            label: Text('下载视频（${_selected.length}）'),
          ),
        ),
      ),
    );
  }

  /// 默认画质：优先「高清 1080P」（qn=80），无则取最高可用档。
  int _defaultQn(List<BiliQualityOption> qualities) {
    if (qualities.isEmpty) return 80;
    for (final q in qualities) {
      if (q.qn == 80) return 80;
    }
    return qualities.first.qn;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
      ));
  }

  String _errText(Object e) => e.toString().replaceFirst('BiliApiException: ', '');
}
