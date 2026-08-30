/// 按文件扩展名 → MIME 类型（移植 mpvRx 的 NetworkMimeTypes）。
library;

const _genericVideoExtensions = {
  'm2v', 'ogv', 'mts', 'm2ts', 'vob', 'divx', 'xvid', 'f4v', 'rm', 'rmvb',
  'asf',
};

const _genericAudioExtensions = {
  'm4a', 'flac', 'ogg', 'oga', 'opus', 'wav', 'wave', 'wma', 'amr', 'awb',
  'ac3', 'eac3', 'dts', 'mka', 'aif', 'aiff', 'aifc', 'ape', 'mp1', 'mp2',
  'mpa', 'mpc', 'tta', 'tak', 'caf', 'au', 'snd', 'ra', 'spx', 'weba', '3ga',
  'dsf', 'dff', 'mlp', 'truehd', 'mid', 'midi',
};

String? networkMimeTypeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'm3u':
    case 'm3u8':
      return 'application/vnd.apple.mpegurl';
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'avi':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    case 'wmv':
      return 'video/x-ms-wmv';
    case 'flv':
      return 'video/x-flv';
    case 'webm':
      return 'video/webm';
    case 'mpeg':
    case 'mpg':
      return 'video/mpeg';
    case '3gp':
      return 'video/3gpp';
    case '3g2':
      return 'video/3gpp2';
    case 'ts':
      return 'video/mp2t';
    case 'm4s':
      return 'video/iso.segment';
    case 'aac':
      return 'audio/aac';
    case 'mp3':
      return 'audio/mpeg';
    case 'vtt':
      return 'text/vtt';
    case 'srt':
    case 'ass':
    case 'ssa':
      return 'text/plain';
  }
  if (_genericVideoExtensions.contains(ext)) return 'video/*';
  if (_genericAudioExtensions.contains(ext)) return 'audio/*';
  return null;
}

/// 判断文件名是否为视频（用于网络浏览时过滤出可播放的视频条目）。
/// 仅当按扩展名能映射到 `video/*` 时返回 true；未知扩展名（无法确定）返回 false。
bool isNetworkVideoFile(String fileName) {
  final mime = networkMimeTypeForFileName(fileName);
  return mime != null && mime.startsWith('video/');
}