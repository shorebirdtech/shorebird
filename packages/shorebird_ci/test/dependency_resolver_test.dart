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

      test('workspaceFiles names the root pubspec files', () {
        createWorkspaceRoot(tempDir, members: ['packages/app']);
        writeMember('packages/app', 'app', '');
        createPackage(tempDir, 'tools/solo', 'solo');

        final resolver = DependencyResolver(tempDir.path);

        expect(
          resolver.workspaceFiles('packages/app'),
          equals({'pubspec.yaml', 'pubspec.lock'}),
        );
        expect(resolver.workspaceFiles('tools/solo'), isEmpty);
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

    group('submodule mount-point collapse', () {
      test(
        'collapses dependencies inside a .gitmodules path to the mount point',
        () {
          File(p.join(tempDir.path, '.gitmodules')).writeAsStringSync('''
[submodule "vendor/sdk"]
\tpath = vendor/sdk
\turl = https://example.com/sdk.git
''');
          createPackage(tempDir, 'vendor/sdk/packages/core', 'core');
          createPackage(
            tempDir,
            'vendor/sdk/packages/helper',
            'helper',
            dependencies: {'core': '../core'},
          );
          createPackage(
            tempDir,
            'packages/app',
            'app',
            dependencies: {'helper': '../../vendor/sdk/packages/helper'},
          );

          final resolver = DependencyResolver(tempDir.path);
          expect(resolver.submodulePaths, equals({'vendor/sdk'}));
          expect(resolver.isSubmodule('vendor/sdk'), isTrue);
          expect(resolver.isSubmodule('packages/app'), isFalse);
          expect(
            resolver.resolve('packages/app'),
            equals({'packages/app', 'vendor/sdk'}),
          );
          expect(
            resolver.filterPaths(
              'packages/app',
              workflowFile: '.github/workflows/_shorebird_ci_dart.yaml',
            ),
            equals([
              '.github/workflows/_shorebird_ci_dart.yaml',
              'packages/app/**',
              'vendor/sdk',
            ]),
          );
        },
      );
    });

    group('extraInputs', () {
      test(
        'reads shorebird_ci.inputs and verify_cache.inputs from pubspec.yaml',
        () {
          File(p.join(tempDir.path, '.gitmodules')).writeAsStringSync('''
[submodule "third_party/sub"]
\tpath = third_party/sub
\turl = https://example.com/sub.git
''');
          File(
              p.join(tempDir.path, 'packages', 'app', 'assets', 'schema.json'),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('{}');

          File(
              p.join(tempDir.path, 'packages', 'app', 'pubspec.yaml'),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('''
name: app
environment:
  sdk: ^3.0.0
shorebird_ci:
  inputs:
    - ../../openapi.yaml
    - scripts/**
    - ../../third_party/sub/file.txt
verify_cache:
  inputs:
    - assets/schema.json
    - ./local_config.yaml
''');

          final resolver = DependencyResolver(tempDir.path);
          expect(
            resolver.extraInputs('packages/app'),
            equals({
              'openapi.yaml',
              'scripts/**',
              'third_party/sub',
              'packages/app/assets/schema.json',
              'packages/app/local_config.yaml',
            }),
          );
        },
      );
    });
  });
}
