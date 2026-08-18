import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moumou/services/video_info_service.dart';

/// 媒体信息页：点击视频卡片最右侧的「i」图标进入，
/// 用 MediaInfoLib 解析并展示 通用信息 / 视频流 / 音频流 / 字幕流。
class MediaInfoPage extends StatefulWidget {
  final String path;
  final String title;

  const MediaInfoPage({
    super.key,
    required this.path,
    required this.title,
  });

  @override
  State<MediaInfoPage> createState() => _MediaInfoPageState();
}

class _MediaInfoPageState extends State<MediaInfoPage> {
  Map<String, dynamic>? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await VideoInfoService.getMediaInfo(widget.path);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final info = _info;
    if (info == null) return;
    await Clipboard.setData(ClipboardData(text: _formatText(info)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('媒体信息已复制'),
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _formatText(Map<String, dynamic> info) {
    final buf = StringBuffer()
      ..writeln('媒体信息 - ${widget.title}')
      ..writeln('=' * 40);
    final general = info['general'] as Map?;
    if (general != null && general.isNotEmpty) {
      buf.writeln('【通用信息】');
      general.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) buf.writeln('$k: $v');
      });
      buf.writeln();
    }
    _formatStreams(buf, '视频流', info['videoStreams']);
    _formatStreams(buf, '音频流', info['audioStreams']);
    _formatStreams(buf, '字幕流', info['textStreams']);
    return buf.toString();
  }

  void _formatStreams(StringBuffer buf, String title, dynamic list) {
    if (list is! List || list.isEmpty) return;
    buf.writeln('【$title】');
    for (final item in list) {
      final m = Map<String, dynamic>.from(item as Map);
      buf.writeln('- ${m.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' | ')}');
    }
    buf.writeln();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_info != null)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: '复制',
              onPressed: _copy,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _info == null
              ? const Center(child: Text('媒体信息获取失败'))
              : _buildInfo(scheme),
    );
  }

  Widget _buildInfo(ColorScheme scheme) {
    final info = _info!;
    final general = info['general'] as Map? ?? const {};
    final videoStreams = info['videoStreams'] as List? ?? const [];
    final audioStreams = info['audioStreams'] as List? ?? const [];
    final textStreams = info['textStreams'] as List? ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (general.isNotEmpty) ...[
          _sectionTitle(scheme, '通用信息'),
          _infoCard(
            scheme,
            [
              if (_nonEmpty(general['format'])) ('格式', general['format']! as String),
              if (_nonEmpty(general['formatVersion'])) ('格式版本', general['formatVersion']! as String),
              if (_nonEmpty(general['fileSize'])) ('文件大小', general['fileSize']! as String),
              if (_nonEmpty(general['duration'])) ('时长', general['duration']! as String),
              if (_nonEmpty(general['overallBitRate'])) ('总比特率', general['overallBitRate']! as String),
              if (_nonEmpty(general['frameRate'])) ('帧率', general['frameRate']! as String),
              if (_nonEmpty(general['title'])) ('标题', general['title']! as String),
              if (_nonEmpty(general['encodedDate'])) ('编码日期', general['encodedDate']! as String),
              if (_nonEmpty(general['writingApplication'])) ('编码应用', general['writingApplication']! as String),
              if (_nonEmpty(general['writingLibrary'])) ('编码库', general['writingLibrary']! as String),
            ],
          ),
        ],
        if (videoStreams.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(scheme, '视频流'),
          for (var i = 0; i < videoStreams.length; i++)
            _infoCard(scheme, _streamRows(videoStreams[i] as Map, '视频流 #${i + 1}')),
        ],
        if (audioStreams.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(scheme, '音频流'),
          for (var i = 0; i < audioStreams.length; i++)
            _infoCard(scheme, _streamRows(audioStreams[i] as Map, '音频流 #${i + 1}')),
        ],
        if (textStreams.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(scheme, '字幕流'),
          for (var i = 0; i < textStreams.length; i++)
            _infoCard(scheme, _streamRows(textStreams[i] as Map, '字幕流 #${i + 1}')),
        ],
        if (general.isEmpty &&
            videoStreams.isEmpty &&
            audioStreams.isEmpty &&
            textStreams.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('未获取到媒体信息')),
          ),
      ],
    );
  }

  List<(String, String)> _streamRows(Map stream, String title) {
    const labelMap = {
      'id': 'ID',
      'format': '编码',
      'formatProfile': '配置',
      'codecId': '编码ID',
      'width': '宽',
      'height': '高',
      'displayAspectRatio': '宽高比',
      'frameRate': '帧率',
      'frameRateMode': '帧率模式',
      'bitRate': '比特率',
      'bitDepth': '位深度',
      'colorSpace': '色彩空间',
      'chromaSubsampling': '色度子采样',
      'hdrFormat': 'HDR格式',
      'channels': '声道',
      'samplingRate': '采样率',
      'language': '语言',
      'title': '标题',
      'duration': '时长',
      'streamSize': '流大小',
    };
    final rows = <(String, String)>[
      for (final e in stream.entries)
        if (_nonEmpty(e.value))
          (labelMap[e.key] ?? e.key, e.value.toString()),
    ];
    // 标题行信息不足时至少保留流序号
    if (rows.isEmpty) rows.add(('流', title));
    return rows;
  }

  bool _nonEmpty(dynamic v) => v != null && v.toString().isNotEmpty;

  Widget _sectionTitle(ColorScheme scheme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _infoCard(ColorScheme scheme, List<(String, String)> rows) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        row.$1,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
