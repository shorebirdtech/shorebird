import 'package:cutler/config.dart';
import 'package:test/test.dart';

void main() {
  test('expandUser', () {
    final path = expandUser('~/foo/bar', env: {'HOME': '/home/user'});
    expect(path, endsWith('/home/user/foo/bar'));

    // HOME is not set.
    expect(() => expandUser('~/foo/bar', env: {}), throwsA(isA<Exception>()));
  });

  test('packageRootFromScriptPath', () {
    // Using Platform.script.path inside a test is sometimes a
    // .dill file (from package test) or sometimes a snapshot
    // e.g. from very_good test.
    expect(findPackageRoot(scriptPath: '/foo/bar/bin/baz.dart'), '/foo/bar');
    expect(
      findPackageRoot(
        scriptPath:
            '/src/foo/.dart_tool/pub/bin/cutler/cutler.dart-3.0.2.snapshot',
      ),
      '/src/foo/',
    );
    expect(
      () => findPackageRoot(scriptPath: '/invalid'),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
