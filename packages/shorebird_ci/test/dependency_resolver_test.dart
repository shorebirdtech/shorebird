import 'dart:io';

import 'package:path/path.dart' as p;
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

    group('workspace members', () {
      // A member depending on another by name alone, as pub resolves
      // `scoped_deps: ^0.1.0` to the workspace's scoped_deps.
      void writeMember(String relativePath, String name, String deps) {
        final dir = Directory(p.join(tempDir.path, relativePath))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
resolution: workspace
environment:
  sdk: ^3.0.0
$deps''');
      }

      test('resolves a member depended on by name alone', () {
        createWorkspaceRoot(
          tempDir,
          members: ['packages/app', 'packages/lib_a', 'packages/lib_b'],
        );
        writeMember('packages/lib_b', 'lib_b', '');
        writeMember('packages/lib_a', 'lib_a', '''
dependencies:
  lib_b: ^1.0.0
''');
        writeMember('packages/app', 'app', '''
dependencies:
  lib_a: ^1.0.0
  path: ^1.9.0
''');

        final deps = DependencyResolver(tempDir.path).resolve('packages/app');

        expect(
          deps,
          equals({'packages/app', 'packages/lib_a', 'packages/lib_b'}),
        );
      });

      test('ignores a name match outside the workspace', () {
        createWorkspaceRoot(tempDir, members: ['packages/app']);
        writeMember('packages/app', 'app', '''
dependencies:
  other: ^1.0.0
''');
        createPackage(tempDir, 'packages/other', 'other');

        final deps = DependencyResolver(tempDir.path).resolve('packages/app');

        expect(deps, equals({'packages/app'}));
      });

      test('ignores names for a package without workspace resolution', () {
        createWorkspaceRoot(tempDir, members: ['packages/lib_a']);
        writeMember('packages/lib_a', 'lib_a', '');
        File(
            p.join(tempDir.path, 'packages', 'app', 'pubspec.yaml'),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('''
name: app
environment:
  sdk: ^3.0.0
dependencies:
  lib_a: ^1.0.0
''');

        final deps = DependencyResolver(tempDir.path).resolve('packages/app');

        expect(deps, equals({'packages/app'}));
      });
    });
  });
}
