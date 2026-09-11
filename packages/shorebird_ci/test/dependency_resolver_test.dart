import 'package:shorebird_ci/shorebird_ci.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  setUpTempDir('shorebird_ci_dep_resolver_');

  group('DependencyResolver', () {
    test('resolves direct path dependencies', () {
      createPackage(tempDir, 'packages/package_b', 'package_b');
      createPackage(
        tempDir,
        'packages/package_a',
        'package_a',
        dependencies: {'package_b': '../package_b'},
      );

      final resolver = DependencyResolver(tempDir.path);
      final deps = resolver.resolve('packages/package_a');

      expect(
        deps,
        containsAll(['packages/package_a', 'packages/package_b']),
      );
    });

    test('resolves transitive path dependencies', () {
      createPackage(tempDir, 'packages/package_c', 'package_c');
      createPackage(
        tempDir,
        'packages/package_b',
        'package_b',
        dependencies: {'package_c': '../package_c'},
      );
      createPackage(
        tempDir,
        'packages/package_a',
        'package_a',
        dependencies: {'package_b': '../package_b'},
      );

      final resolver = DependencyResolver(tempDir.path);
      final deps = resolver.resolve('packages/package_a');

      expect(
        deps,
        containsAll([
          'packages/package_a',
          'packages/package_b',
          'packages/package_c',
        ]),
      );
    });

    test('handles packages with no dependencies', () {
      createPackage(tempDir, 'packages/standalone', 'standalone');

      final resolver = DependencyResolver(tempDir.path);
      final deps = resolver.resolve('packages/standalone');

      expect(deps, equals({'packages/standalone'}));
    });

    test('handles cycles without looping forever', () {
      createPackage(
        tempDir,
        'packages/a',
        'a',
        dependencies: {'b': '../b'},
      );
      createPackage(
        tempDir,
        'packages/b',
        'b',
        dependencies: {'a': '../a'},
      );

      final resolver = DependencyResolver(tempDir.path);
      final deps = resolver.resolve('packages/a');

      expect(deps, equals({'packages/a', 'packages/b'}));
    });

    test('handles packages at non-standard paths', () {
      createPackage(tempDir, 'libs/util', 'util');
      createPackage(
        tempDir,
        'apps/server',
        'server',
        dependencies: {'util': '../../libs/util'},
      );

      final resolver = DependencyResolver(tempDir.path);
      final deps = resolver.resolve('apps/server');

      expect(deps, containsAll(['apps/server', 'libs/util']));
    });
  });
}
