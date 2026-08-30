import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/webdav_xml.dart';

void main() {
  test('percentDecode 基本解码', () {
    expect(percentDecode('a%20b'), 'a b');
    expect(percentDecode('%E4%B8%AD'), '中');
    expect(percentDecode('no-percent'), 'no-percent');
    expect(percentDecode('bad%xxy'), 'bad%xxy'); // 非法序列原样保留
  });

  test('parseHttpDate 解析 RFC1123 日期', () {
    final ms = parseHttpDate('Sun, 06 Nov 1994 08:49:37 GMT');
    expect(ms, DateTime.utc(1994, 11, 6, 8, 49, 37).millisecondsSinceEpoch);
    expect(parseHttpDate('not a date'), 0);
    expect(parseHttpDate(''), 0);
  });

  test('parseWebDavMultistatus 解析目录与文件', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/movies/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
      <d:getlastmodified>Mon, 01 Jan 2024 00:00:00 GMT</d:getlastmodified>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/movies/a%20movie.mp4</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getcontentlength>123456</d:getcontentlength>
      <d:getlastmodified>Tue, 02 Jan 2024 01:02:03 GMT</d:getlastmodified>
    </d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';
    final resources = parseWebDavMultistatus(xml);
    expect(resources.length, 2);

    final dir = resources[0];
    expect(dir.href, '/movies/');
    expect(dir.name, 'movies');
    expect(dir.isDirectory, isTrue);
    expect(dir.contentLength, -1);

    final file = resources[1];
    expect(file.href, '/movies/a movie.mp4');
    expect(file.name, 'a movie.mp4');
    expect(file.isDirectory, isFalse);
    expect(file.contentLength, 123456);
    expect(file.lastModifiedMs, DateTime.utc(2024, 1, 2, 1, 2, 3).millisecondsSinceEpoch);
  });

  test('parseWebDavMultistatus 跳过无 href 的块', () {
    const xml = '''
<d:multistatus xmlns:d="DAV:">
  <d:response><d:propstat><d:prop/></d:propstat></d:response>
  <d:response><d:href>/ok.mp4</d:href><d:propstat><d:prop><d:getcontentlength>9</d:getcontentlength></d:prop></d:propstat></d:response>
</d:multistatus>
''';
    final resources = parseWebDavMultistatus(xml);
    expect(resources.length, 1);
    expect(resources[0].name, 'ok.mp4');
  });
}