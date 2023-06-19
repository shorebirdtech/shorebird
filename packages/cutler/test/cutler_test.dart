import 'package:cutler/config.dart';
import 'package:test/test.dart';

void main() {
  test('expandUser', () {
    final path = expandUser('~/foo/bar', env: {'HOME': '/home/user'});
    expect(path, endsWith('/home/user/foo/bar'));
  });
}
