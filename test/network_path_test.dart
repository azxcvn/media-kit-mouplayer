import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/utils/network_path.dart';

void main() {
  test('根路径与空路径归一化为 /', () {
    expect(NetworkPath.from('').value, '/');
    expect(NetworkPath.from('/').value, '/');
    expect(NetworkPath.from('///').value, '/');
    expect(NetworkPath.root.isRoot, isTrue);
  });

  test('普通路径规范化', () {
    expect(NetworkPath.from('a/b/c').value, '/a/b/c');
    expect(NetworkPath.from('/a//b/').value, '/a/b');
    expect(NetworkPath.from('A/B').value, '/A/B');
  });

  test('relative 去掉前导斜杠', () {
    expect(NetworkPath.from('/a/b').relative, 'a/b');
    expect(NetworkPath.root.relative, '');
  });

  test('child 拼接', () {
    final root = NetworkPath.from('/movies');
    expect(root.child('年度').value, '/movies/年度');
    expect(NetworkPath.root.child('x').value, '/x');
  });

  test('segments 拆分', () {
    expect(NetworkPath.from('/a/b/c').segments, ['a', 'b', 'c']);
    expect(NetworkPath.root.segments, isEmpty);
  });

  test('拒绝非法路径', () {
    expect(() => NetworkPath.from('http://x/y'), throwsArgumentError);
    expect(() => NetworkPath.from('a/../b'), throwsArgumentError);
    expect(() => NetworkPath.from('a/./b'), throwsArgumentError);
    expect(() => NetworkPath.from(r'a\b'), throwsArgumentError);
    expect(() => NetworkPath.from('a/\u0000b'), throwsArgumentError);
  });
}