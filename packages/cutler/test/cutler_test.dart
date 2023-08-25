import 'package:cutler/config.dart';
import 'package:test/test.dart';

void main() {
  test('expandUser', () {
    final path = expandUser('~/foo/bar', env: {'HOME': '/home/user'});
    expect(path, endsWith('/home/user/foo/bar'));

    // HOME is not set.
    expect(() => expandUser('~/foo/bar', env: {}), throwsA(isA<Exception>()));
  });

  test('findPackageRoot', () {
    // Should throw an exception with the string 'test' in it.
    expect(
      findPackageRoot,
      throwsA(
        isA<UnimplementedError>().having(
          (e) => e.message,
          'message',
          contains('test'),
        ),
      ),
    );
  });
}
